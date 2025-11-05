import argparse
from typing import List
from pprint import pprint
import numpy as np #only for printing

# --- UNCHANGED ---
def read_signal(path: str) -> List[float]:
    with open(path, "r") as f:
        return list(map(float, f.readlines()[0].strip().split()))

# --- UNCHANGED ---
def autocorr_biased(x: List[float], maxlag: int) -> List[float]:
    N = len(x)
    r = []
    for k in range(maxlag + 1):
        s = 0.0
        for n in range(k, N):
            s += x[n] * x[n - k]
        r.append(s / N)  # biased (divide by N)
    return r

# <--- MODIFIED to accept a min/max lag range ---
def crosscorr_biased(x: List[float], d: List[float], minlag: int, maxlag: int) -> List[float]:
    """
    Computes the biased cross-correlation p(k) = E[d(n) * x(n-k)]
    for k from minlag to maxlag.
    """
    N = len(x)
    p = []
    # Loop over the entire specified lag range
    for k in range(minlag, maxlag + 1):
        s = 0.0
        
        # We need to find the valid summation range for 'n'
        # where both d[n] and x[n-k] are valid.
        # 1.  0 <= n < N       (for d[n])
        # 2.  0 <= n-k < N   =>  k <= n < N+k
        #
        # We need n to be in the intersection of [0, N) and [k, N+k)
        # The intersection is [max(0, k), min(N, N+k))
        
        start_n = max(0, k)
        end_n = min(N, N + k)
        
        for n in range(start_n, end_n):
            s += d[n] * x[n - k]
        p.append(s / N)
    return p

# --- UNCHANGED ---
def toeplitz_from_r(r: List[float], M: int) -> List[List[float]]:
    return [[r[abs(i - j)] for j in range(M)] for i in range(M)]

# --- UNCHANGED ---
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

# <--- MODIFIED to accept a 'delay' and apply a non-causal filter ---
def apply_fir(x: List[float], w: List[float], delay: int) -> List[float]:
    """
    Applies the filter w to signal x.
    w[k] corresponds to the tap for lag (k - delay).
    y[n] = sum( w[k] * x[n - k + delay] )
    """
    N = len(x)
    M = len(w)
    y = [0.0] * N
    for n in range(N):
        s = 0.0
        for k in range(M):
            # This is the index into the signal 'x'
            idx = n - k + delay
            
            # Check boundaries:
            if idx < 0:
                # This tap is looking at data before the signal starts
                continue
            if idx >= N:
                # This tap is looking at data after the signal ends
                continue
                
            s += w[k] * x[idx]
        y[n] = s
    return y

# <--- MODIFIED to set up the non-causal problem ---
def main():
    parser = argparse.ArgumentParser(description="Non-Causal Wiener filter (pure Python)")
    parser.add_argument("--input", default="input.txt")
    parser.add_argument("--desired", default="desired.txt")
    parser.add_argument("--order", type=int, default=11) # Default to odd
    args = parser.parse_args()

    x = read_signal(args.input)
    d = read_signal(args.desired)
    print(len(x), len(d))
    if len(x) != len(d):
        raise ValueError("input and desired must have same length")

    M = args.order
    # For a symmetric non-causal filter, the order M must be odd.
    if M % 2 == 0:
        M += 1
        print(f"Warning: Order M must be odd for a symmetric filter. Rounding up to M={M}")

    # 'delay' is the index of the "center" tap (w[0])
    # e.g., M=11, delay=5. Taps are for lags -5, -4, ..., 0, ..., 4, 5
    delay = (M - 1) // 2
    
    # 1. Autocorrelation (unchanged logic)
    # We still need r[0...M-1] to build the MxM Toeplitz matrix
    r = autocorr_biased(x, M - 1)
    
    # 2. Cross-correlation (NEW logic)
    # We need p(k) for k from -delay to +delay.
    minlag = -delay
    maxlag = delay
    p = crosscorr_biased(x, d, minlag, maxlag) # This vector will have M elements

    # 3. Build Toeplitz Matrix R (unchanged logic)
    R = toeplitz_from_r(r, M)
    with open("r_matrix.txt", "w") as file:
        for line in R:
            file.write(f"{list(map(lambda x : round(x, 1), line))}\n")

    # 4. Solve R w = p (unchanged logic)
    # w will be an M-element vector.
    # w[0] corresponds to p[minlag]
    # w[delay] corresponds to p[0]
    w = solve_linear(R, p)

    # 5. Apply the non-causal filter (NEW logic)
    y = apply_fir(x, w, delay)
    
    # 6. Compute MSE (unchanged logic)
    # This calculation is still valid.
    mse = sum((di - yi) ** 2 for di, yi in zip(d, y)) / len(d)
    
    # 7. Compute MMSE (unchanged logic)
    # This formula is still E[d^2] - p'w, which is exactly what this code does.
    mmse = sum(di**2 for di in d) / len(d) - sum(pi * wi for pi, wi in zip(p, w))
    
    # 8. Save (unchanged logic)
    with open("wiener_coeffs.txt", "w") as f:
        f.write(f"# Non-causal filter, M={M}, delay={delay}\n")
        f.write(f"# w[k] corresponds to lag = k - {delay}\n")
        for k, wi in enumerate(w):
            f.write(f"w[{k:02d}] (lag={k-delay: d}): {wi:.6f}\n")
            
    with open("wiener_output.txt", "w") as f:
        for yi in y:
            f.write(f"{yi:.6f} ")

    print(f"Type=Non-Causal, Order={M}, Delay={delay}")
    print(f"MSE (measured)={mse:.6f}, MMSE (predicted)={mmse:.6f}")

if __name__ == "__main__":
    main()