"""Conservative, deterministic yaku guidance for each post-call discard.

Completed waits use the scoring engine. Incomplete hands use explicitly
conditional routes, never an exhaustive claim that no yaku is possible.
"""
from collections import Counter

from app.domain.tiles import normalize_tile
from app.schemas import (
    CallAnalysisRequest, CallOutlook, CallScoreEstimate, CallWinningTile,
    CallYakuProspect, WaitAnalysis,
)
from app.scoring.payments import calculate_payments


BONUS_NAMES = {"ドラ", "赤ドラ", "裏ドラ"}
NO_YAKU_ERROR = "No yaku: dora-only hands cannot win"


def _simple(tile: str) -> bool:
    return len(tile) == 2 and tile[0] in "2345678"


def call_warnings(request: CallAnalysisRequest) -> list[str]:
    warnings = []
    if not request.rules.kuitan_ari:
        warnings.append("喰いタンなしの設定では、鳴くとタンヤオは成立しません。")
    elif any(not _simple(normalize_tile(tile)) for meld in request.melds for tile in meld.tiles):
        warnings.append("副露に1・9・字牌が固定されるため、タンヤオは成立しません。")
    # The final meld is the hypothetical call; only the first open call loses menzen.
    if not any(meld.open for meld in request.melds[:-1]):
        warnings.append("鳴くとリーチ・門前ツモ・平和・一盃口など門前限定の役は使えません。")
    return warnings


def _prospects(request: CallAnalysisRequest, tiles: list[str]) -> list[CallYakuProspect]:
    closed = Counter(normalize_tile(tile) for tile in tiles)
    fixed = [tuple(sorted(normalize_tile(tile) for tile in meld.tiles)) for meld in request.melds]
    all_tiles = list(closed.elements()) + [tile for meld in fixed for tile in meld]
    counts = Counter(all_tiles)
    prospects = []

    def add(name: str, han: int, condition: str):
        prospects.append(CallYakuProspect(name=name, han=han, condition=condition))

    values = [("P", "役牌 白"), ("F", "役牌 發"), ("C", "役牌 中")]
    if request.context is not None:
        names = {"E": "東", "S": "南", "W": "西", "N": "北"}
        values += [(request.context.round_wind, f"場風 {names[request.context.round_wind]}"),
                   (request.context.seat_wind, f"自風 {names[request.context.seat_wind]}")]
    for tile, name in values:
        if any(meld[0] == tile and len(set(meld)) == 1 for meld in fixed):
            add(name, 1, "役牌の刻子・槓子を副露済み。残りを和了形にすれば役が付きます。")
        elif closed[tile] >= 2 and len(fixed) < 4:
            add(name, 1, f"{name}を刻子（3枚）にして和了形を作る必要があります。")

    if request.rules.kuitan_ari and all(_simple(tile) for meld in fixed for tile in meld):
        outside = sum(count for tile, count in closed.items() if not _simple(tile))
        if outside <= 2:
            add("断么九", 1, "タンヤオ：手牌の1・9・字牌をすべてなくし、2〜8だけで和了形を作ります。")

    # Require at least seven of the nine sequence tiles, at least two per
    # missing sequence, and room for all three sequences among four melds.
    # Tiles locked in an unrelated meld cannot contribute to a target sequence.
    def sequence_route(sequences: list[tuple[str, ...]]) -> bool:
        remaining = list(sequences)
        for meld, shape in zip(request.melds, fixed):
            if meld.type == "chi" and shape in remaining:
                remaining.remove(shape)
        if len(remaining) > 4 - len(fixed):
            return False
        needed = Counter(tile for sequence in remaining for tile in sequence)
        if any(sum(tile in closed for tile in sequence) < 2 for sequence in remaining):
            return False
        missing = sum(max(0, count - closed[tile]) for tile, count in needed.items())
        # Do not suggest a fifth copy that is already locked in another meld.
        if any(count + sum(shape.count(tile) for shape in fixed) > 4 for tile, count in needed.items()):
            return False
        return missing <= 2

    for start in range(1, 8):
        sequences = [tuple(f"{rank}{suit}" for rank in range(start, start + 3)) for suit in "mps"]
        if sequence_route(sequences):
            ranks = "".join(str(rank) for rank in range(start, start + 3))
            add("三色同順", 1, f"萬子・筒子・索子で{ranks}の順子をそろえ、和了形を作ると成立。鳴くと2翻→1翻。")
    for suit, label in zip("mps", ("萬子", "筒子", "索子")):
        sequences = [tuple(f"{rank}{suit}" for rank in range(start, start + 3)) for start in (1, 4, 7)]
        if sequence_route(sequences):
            add("一気通貫", 1, f"{label}で123・456・789の順子をそろえて和了すると成立。鳴くと2翻→1翻。")
        if all(len(tile) == 1 or tile[1] == suit for shape in fixed for tile in shape):
            off_suit = sum(count for tile, count in closed.items() if len(tile) == 2 and tile[1] != suit)
            if off_suit <= 2 and sum(count for tile, count in counts.items() if len(tile) == 2 and tile[1] == suit) >= 7:
                honors = any(len(tile) == 1 for tile in all_tiles)
                add("混一色" if honors else "清一色", 2 if honors else 5,
                    f"{label}{'と字牌だけ' if honors else 'だけ'}で和了形を作る必要があります。鳴くと1翻下がります。")
    if all(meld.type != "chi" for meld in request.melds) and len(fixed) + sum(count >= 2 for count in closed.values()) >= 4:
        add("対々和", 2, "4組すべてを刻子・槓子にし、別に雀頭を作る必要があります。")
    return prospects


def _basis(request: CallAnalysisRequest) -> str:
    role = "親" if request.context.seat_wind == "E" else "子"
    return f"{role}のロン・本場/供託を除く"


def assess_call_branch(
    request: CallAnalysisRequest, tiles: list[str], shanten: int, waits: list[WaitAnalysis],
    tsumo_waits: list[WaitAnalysis] | None = None,
) -> CallOutlook:
    warnings = call_warnings(request)
    live_waits = [wait for wait in waits if wait.remaining > 0]
    if shanten == 0 and request.context is not None and live_waits:
        winning = []
        no_yaku = []
        yaku = {}
        ron_points = []
        tsumo_points = []
        live_tsumo = [wait for wait in (tsumo_waits or []) if wait.remaining > 0]
        assessed = set()
        for win_type, wait in [*(('ron', wait) for wait in live_waits), *(('tsumo', wait) for wait in live_tsumo)]:
            if wait.score is not None:
                score = wait.score
                names = [item.name for item in score.yaku if item.name not in BONUS_NAMES] + score.yakuman
                for item in score.yaku:
                    if item.name not in BONUS_NAMES:
                        yaku[item.name] = CallYakuProspect(name=item.name, han=item.han, condition="詳細の役が付く待ち牌で和了した場合。")
                for name in score.yakuman:
                    yaku[name] = CallYakuProspect(name=name, han=13, condition="詳細の役が付く待ち牌で和了した場合（役満）。")
                assessed.add((win_type, wait.tile))
                if win_type == 'ron':
                    ron_points.append(score.points.ron)
                else:
                    tsumo_points.append(score.payments.hand_points_received)
                winning.append(CallWinningTile(tile=wait.tile, yaku=names, han=score.han, fu=score.fu,
                                               win_type=win_type,
                                               ron_points=score.points.ron if request.include_score_predictions and win_type == 'ron' else None,
                                               tsumo_dealer_pay=score.points.tsumo_dealer_pay if request.include_score_predictions and win_type == 'tsumo' else None,
                                               tsumo_non_dealer_pay=score.points.tsumo_non_dealer_pay if request.include_score_predictions and win_type == 'tsumo' else None))
            elif wait.score_error == NO_YAKU_ERROR:
                assessed.add((win_type, wait.tile))
        winning_names = {wait.tile for wait in winning}
        no_yaku = [wait.tile for wait in live_waits if wait.tile not in winning_names
                   and ('ron', wait.tile) in assessed and ('tsumo', wait.tile) in assessed]
        if winning:
            status, summary = "available", "役のある和了形あり（打牌・待ち牌を確認）"
            if no_yaku:
                warnings.append("同じテンパイでも役が付かない待ちがあります。役が付く待ちを確認してください。")
            ron_without_yaku = {wait.tile for wait in live_waits if wait.score_error == NO_YAKU_ERROR}
            if any(wait.win_type == 'tsumo' and wait.tile in ron_without_yaku for wait in winning):
                warnings.append("ツモでのみ役が付く待ちがあります。その牌では通常のロンはできません。")
        elif len(no_yaku) == len(live_waits):
            status, summary = "no_yaku", "今の待ちでは役なし。別の役を作る手変わりが必要です。"
            warnings.append("ドラだけでは和了できません。")
        else:
            status, summary = "unknown", "役の判定を完了できませんでした。条件を確認してください。"
        if len(assessed) < len(live_waits) + len(live_tsumo):
            warnings.append("一部の待ちの役・打点は未判定です。")
        estimate = None
        points = ron_points or tsumo_points
        if points and request.include_score_predictions:
            basis = _basis(request) if ron_points else _basis(request).replace('ロン', 'ツモ合計')
            estimate = CallScoreEstimate(min_points=min(points), max_points=max(points),
                                         win_type='ron' if ron_points else 'tsumo',
                                         basis=f"{basis}。役が付く待ちの計算値・入力済みドラを含む。")
        return CallOutlook(status=status, summary=summary, yaku=list(yaku.values()), warnings=warnings,
                           score_estimate=estimate, winning_tiles=winning, no_yaku_tiles=no_yaku)

    prospects = _prospects(request, tiles)
    estimate = None
    if prospects and request.context is not None and request.include_score_predictions:
        ron_context = request.context.model_copy(update={"win_type": "ron"})
        points = [calculate_payments(ron_context, item.han, fu, kazoe_yakuman_ari=request.rules.kazoe_yakuman_ari)[0].ron
                  for item in prospects for fu in (30, 40)]
        estimate = CallScoreEstimate(min_points=min(points), max_points=max(points),
                                    basis=f"{_basis(request)}。各候補役が単独で成立した場合の参考値（30〜40符・ドラなし）。役の複合・実際の符で変動。")
    if shanten == 0 and not live_waits:
        warnings.append("現在の待ち牌は手牌・副露だけで4枚見えており、残りがありません。手変わりが必要です。")
    if request.context is None:
        warnings.append("場風・自風などの場況が未入力のため、役・打点を確定できません。")
    return CallOutlook(
        status="conditional" if prospects else "unknown",
        summary="役を作る条件あり（まだ和了確定ではありません）" if prospects else "和了できる役は未確認。役なしと断定はできません。",
        yaku=prospects, warnings=warnings, score_estimate=estimate,
    )


def summarize_call_outlooks(outlooks: list[CallOutlook]) -> CallOutlook:
    """Union of alternatives; do not add han or promise every discard works."""
    status = next(value for value in ("available", "conditional", "unknown", "no_yaku")
                  if any(outlook.status == value for outlook in outlooks))
    relevant = [outlook for outlook in outlooks if outlook.status == status]
    yaku = {(item.name, item.condition): item for outlook in relevant for item in outlook.yaku}
    warnings = list(dict.fromkeys(warning for outlook in outlooks for warning in outlook.warnings))
    if len({outlook.status for outlook in outlooks}) > 1:
        warnings.append("切る牌によって役の有無が変わります。詳細の打牌ごとの条件を確認してください。")
    estimates = [outlook.score_estimate for outlook in relevant if outlook.score_estimate is not None]
    estimate = None
    if estimates:
        # Never mix ron payments and tsumo totals into the same range.
        if any(item.win_type == 'ron' for item in estimates):
            estimates = [item for item in estimates if item.win_type == 'ron']
        estimate = CallScoreEstimate(min_points=min(item.min_points for item in estimates),
                                    max_points=max(item.max_points for item in estimates), basis=estimates[0].basis,
                                    win_type=estimates[0].win_type)
    # Waits belong to their discard branches. Keep the summary free of a
    # misleading global association between a tile and its yaku/score.
    return CallOutlook(status=status, summary=relevant[0].summary, yaku=list(yaku.values()),
                       warnings=warnings, score_estimate=estimate,
                       no_yaku_tiles=sorted({tile for outlook in outlooks for tile in outlook.no_yaku_tiles}) if status == "no_yaku" else [])
