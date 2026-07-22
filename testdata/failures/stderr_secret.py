import os

os.write(2, b"PYFT_SECRET_CANARY")
raise RuntimeError("PYFT_SECRET_CANARY")
