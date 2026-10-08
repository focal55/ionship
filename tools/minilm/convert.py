import numpy as np, torch, coremltools as ct
from transformers import AutoModel, AutoTokenizer

name = "sentence-transformers/all-MiniLM-L6-v2"
tokenizer = AutoTokenizer.from_pretrained(name)
bert = AutoModel.from_pretrained(name).eval()
LENGTH = 128

class Encoder(torch.nn.Module):
    def __init__(self, bert):
        super().__init__(); self.bert = bert
    def forward(self, input_ids, attention_mask):
        tokens = self.bert(input_ids=input_ids, attention_mask=attention_mask).last_hidden_state
        mask = attention_mask.unsqueeze(-1).to(tokens.dtype)
        pooled = (tokens * mask).sum(1) / mask.sum(1).clamp(min=1e-9)
        return torch.nn.functional.normalize(pooled, dim=1)

encoder = Encoder(bert).eval()
example = tokenizer(["hello there"], padding="max_length", max_length=LENGTH, truncation=True, return_tensors="pt")
traced = torch.jit.trace(encoder, (example["input_ids"], example["attention_mask"]))
model = ct.convert(
    traced,
    inputs=[ct.TensorType(name="input_ids", shape=(1, LENGTH), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, LENGTH), dtype=np.int32)],
    outputs=[ct.TensorType(name="embedding")],
    minimum_deployment_target=ct.target.macOS15,
    compute_precision=ct.precision.FLOAT16,
)
model.short_description = "all-MiniLM-L6-v2 sentence embedding, mean pooled and L2 normalized (Apache-2.0)"
model.save("MiniLM.mlpackage")
tokenizer.save_vocabulary(".")

pairs = [("send you the big sur photos", "did you ever find those pictures from the coast trip"),
         ("send you the big sur photos", "what time is dinner on sunday")]
def coreml(text):
    t = tokenizer([text], padding="max_length", max_length=LENGTH, truncation=True, return_tensors="np")
    return model.predict({"input_ids": t["input_ids"].astype(np.int32), "attention_mask": t["attention_mask"].astype(np.int32)})["embedding"][0]
def torchvec(text):
    t = tokenizer([text], padding="max_length", max_length=LENGTH, truncation=True, return_tensors="pt")
    with torch.no_grad(): return encoder(t["input_ids"], t["attention_mask"])[0].numpy()
for a, b in pairs:
    print(f"coreml sim {float(np.dot(coreml(a), coreml(b))):.3f}  torch sim {float(np.dot(torchvec(a), torchvec(b))):.3f}")
print("max abs diff vs torch:", float(np.abs(coreml(pairs[0][0]) - torchvec(pairs[0][0])).max()))
