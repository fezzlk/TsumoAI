from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def test_compose_uses_tsumoai_project_contract():
    compose = (ROOT / "docker-compose.yml").read_text(encoding="utf-8")

    assert "GOOGLE_CLOUD_PROJECT=${GCP_PROJECT:-tsumoai}" in compose
    assert "GOOGLE_CLOUD_PROJECT=nazonator" not in compose


def test_cloudbuild_targets_the_tsumoai_runtime_identity():
    cloudbuild = (ROOT / "cloudbuild.yaml").read_text(encoding="utf-8")

    assert "_SERVICE: tsumoai-api" in cloudbuild
    assert "tsumoai-runner@tsumoai.iam.gserviceaccount.com" in cloudbuild
    assert "_REGION: asia-northeast1" in cloudbuild
