# MiniLM for Ode

Rebuilds `Ode/MiniLM.mlpackage` and the tokenizer fixtures in OdeCore.

```sh
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python "torch==2.7.0" "transformers>=4.44,<4.50" "sentence-transformers<4" "coremltools>=8" "numpy<2.3"
.venv/bin/python convert.py   # writes MiniLM.mlpackage and vocab.txt, prints Core ML vs PyTorch similarity
.venv/bin/python golden.py    # writes tokenizer-golden.json
```

The pins matter: coremltools 9 fails on NumPy 2.3+ ("only 0-dimensional arrays can be converted to Python scalars").

Verify the Swift pipeline against the reference numbers:

```sh
cd OdeCore && ODE_MODEL_PATH=../Ode/MiniLM.mlpackage swift test --filter SentenceModelEmbedder
```
