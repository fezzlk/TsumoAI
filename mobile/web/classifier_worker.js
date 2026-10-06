let model;
let queue = Promise.resolve();
self.onmessage = ({data}) => {
  queue = queue.then(async () => {
    try {
      if (data.type === 'load') {
        if (!model) {
          importScripts('vendor/tf-core.min.js', 'vendor/tf-backend-cpu.min.js', 'vendor/tf-tflite.min.js');
          await tf.setBackend('cpu');
          await tf.ready();
          tflite.setWasmPath(new URL('vendor/', self.location.href).href);
          model = await tflite.loadTFLiteModel(data.url, {numThreads: 1});
        }
        self.postMessage({id: data.id, result: true});
      } else if (data.type === 'predict') {
        if (!model) throw new Error('牌識別モデルが読み込まれていません');
        const result = tf.tidy(() => {
          const input = tf.tensor(data.input, [1, 224, 224, 3], 'float32');
          const output = model.predict(input);
          return new Float32Array(output.dataSync());
        });
        self.postMessage({id: data.id, result}, [result.buffer]);
      } else {
        throw new Error('不明な牌識別操作です');
      }
    } catch (error) {
      self.postMessage({id: data.id, error: String(error.message || error)});
    }
  });
};
