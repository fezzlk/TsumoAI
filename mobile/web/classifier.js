// Each scan owns a worker; inference never blocks the browser UI thread.
globalThis.createTsumoClassifier = function () {
  const worker = new Worker(new URL('classifier_worker.js', document.baseURI));
  const pending = new Map();
  let nextId = 0;
  let closed = false;
  function failAll(error) {
    for (const {reject, timer} of pending.values()) {
      clearTimeout(timer);
      reject(error);
    }
    pending.clear();
  }
  worker.onmessage = ({data}) => {
    const request = pending.get(data.id);
    if (!request) return;
    pending.delete(data.id);
    clearTimeout(request.timer);
    if (data.error) request.reject(new Error(data.error));
    else request.resolve(data.result);
  };
  worker.onerror = event => {
    closed = true;
    worker.terminate();
    failAll(new Error(event.message || '牌識別を開始できませんでした'));
  };
  function request(type, payload, transfer = []) {
    if (closed) return Promise.reject(new Error('牌識別は終了しました'));
    return new Promise((resolve, reject) => {
      const id = ++nextId;
      const timer = setTimeout(() => {
        closed = true;
        worker.terminate();
        failAll(new Error('牌識別がタイムアウトしました。画面を開き直してください。'));
      }, 120000);
      pending.set(id, {resolve, reject, timer});
      worker.postMessage({id, type, ...payload}, transfer);
    });
  }
  return {
    load(url) { return request('load', {url: new URL(url, document.baseURI).href}); },
    predict(input) {
      const copy = new Float32Array(input);
      return request('predict', {input: copy}, [copy.buffer]);
    },
    dispose() {
      closed = true;
      worker.terminate();
      failAll(new Error('牌識別は終了しました'));
    },
  };
};
