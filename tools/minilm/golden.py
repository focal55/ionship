import json
from transformers import AutoTokenizer
t = AutoTokenizer.from_pretrained("sentence-transformers/all-MiniLM-L6-v2")
cases = [
    "I'll send you the Big Sur photos tonight",
    "I’ll call you after work!!",
    "Café crème brûlée at 9:30am?",
    "lol 😂😂 that was wild",
    "check https://example.com/path?x=1 ok",
    "Ybarra family dinner — Sunday @ 6",
    "unaffable antidisestablishmentarianism",
    "東京 trip next week",
    "   spaces\tand\nnewlines   ",
    "",
    " ".join(["word"] * 200),
]
out = [{"text": c, "ids": t(c, max_length=128, truncation=True)["input_ids"]} for c in cases]
json.dump(out, open("tokenizer-golden.json", "w"), ensure_ascii=False, indent=1)
print(len(out), "cases;", [len(o["ids"]) for o in out])
