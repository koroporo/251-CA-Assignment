import numpy as np

# np.random.seed(0)
result = [float(i + 1) for i in range(10)]

with open("desired.txt", "w") as file:
    for value in result:
        file.write(f"{round(value, 1)} ")