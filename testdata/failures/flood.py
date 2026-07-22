import os
import time

os.write(1, b"x" * 20000)
time.sleep(60)
