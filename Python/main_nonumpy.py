import argparse
from typing import List
from pprint import pprint

def read_signal(path: str) -> List[float]:
    with open(path, "r") as f:
        return list(map(float, f.readlines()[0].strip().split()))

def autocorr_biased(x: List[float], maxlag: int) -> List[float]:
    N = len(x)
    r = []
    for k in range(maxlag + 1):
        s = 0.0
        for n in range(k, N):
            s += x[n] * x[n - k]
        r.append(s / N)  # biased (divide by N)
    return r

def crosscorr_biased(x: List[float], d: List[float], maxlag: int) -> List[float]:
    N = len(x)
    p = []
    for k in range(maxlag + 1):
        s = 0.0
        for n in range(k, N):
            s += d[n] * x[n - k]
        p.append(s / N)
    return p

def toeplitz_from_r(r: List[float], M: int) -> List[List[float]]:
    return [[r[abs(i - j)] for j in range(M)] for i in range(M)]

def solve_linear(A: List[List[float]], b: List[float], eps: float = 1e-12) -> List[float]:
    # Gaussian elimination with partial pivoting (in-place copy)
    n = len(b)
    # make deep copies
    M = [row[:] for row in A]
    y = b[:]
    for k in range(n):
        # pivot
        piv = k
        maxv = abs(M[k][k])
        for i in range(k+1, n):
            if abs(M[i][k]) > maxv:
                maxv = abs(M[i][k]); piv = i
        if maxv < eps:
            # regularize tiny pivot
            M[k][k] += eps
            maxv = abs(M[k][k])
        if piv != k:
            M[k], M[piv] = M[piv], M[k]
            y[k], y[piv] = y[piv], y[k]
        # eliminate
        for i in range(k+1, n):
            if M[k][k] == 0:
                factor = 0.0
            else:
                factor = M[i][k] / M[k][k]
            y[i] -= factor * y[k]
            for j in range(k, n):
                M[i][j] -= factor * M[k][j]
    # back substitution
    x = [0.0] * n
    for i in range(n-1, -1, -1):
        s = y[i]
        for j in range(i+1, n):
            s -= M[i][j] * x[j]
        if abs(M[i][i]) < eps:
            x[i] = s / (M[i][i] + eps)
        else:
            x[i] = s / M[i][i]
    return x

def apply_fir(x: List[float], w: List[float]) -> List[float]:
    N = len(x)
    M = len(w)
    y = [0.0] * N
    for n in range(N):
        s = 0.0
        for k in range(M):
            idx = n - k
            if idx < 0:
                break
            s += w[k] * x[idx]
        y[n] = s
    return y

def main():
    parser = argparse.ArgumentParser(description="Barebones Wiener filter (pure Python)")
    parser.add_argument("--input", default="input.txt")
    parser.add_argument("--desired", default="desired.txt")
    parser.add_argument("--order", type=int, default=10)
    args = parser.parse_args()

    x = read_signal(args.input)
    d = read_signal(args.desired)
    print(len(x), len(d))
    if len(x) != len(d):
        raise ValueError("input and desired must have same length")

# repeatedly applying the filter to converge to a result
    M = args.order
    r = autocorr_biased(x, M - 1)        # r[0..M-1]
    p = crosscorr_biased(x, d, M - 1)    # p[0..M-1]
    print(f"Autocorr: {list(map(lambda x : round(x, 1), r))}")
    print(f"Crosscorr: {list(map(lambda x : round(x, 1), p))}")
    R = toeplitz_from_r(r, M)
    with open("r_matrix.txt", "w") as file:
        for line in R:
            file.write(f"{list(map(lambda x : round(x, 1), line))}\n")
    # print(R)
    # solve R w = p
    w = solve_linear(R, p)
    print(f"Solution: {list(map(lambda x : round(x, 4), w))}")

    y = apply_fir(x, w)
    print(f"Output signal: {list(map(lambda x : round(x, 1), y))}")
    x = y
    # compute MSE
    mse = sum((di - yi) ** 2 for di, yi in zip(d, y)) / len(d)
    
    # compute MMSE
    mmse = sum(di**2 for di in d) / len(d) - sum(pi * wi for pi, wi in zip(p, w))
    

    # save
    with open("wiener_coeffs.txt", "w") as f:
        for wi in w:
            f.write(f"{wi:.6f}\n")
    with open("wiener_output.txt", "w") as f:
        for yi in y:
            f.write(f"{yi:.6f} ")

    print(f"Order={M}, MSE={mse:.6f}, MMSE={mmse:.6f}")

if __name__ == "__main__":
    main()