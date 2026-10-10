"""Locate original artwork inside reference screenshots (masked normalized cross correlation)."""
import numpy as np
from PIL import Image

def prepare(shot_rgb):
    H, W, _ = shot_rgb.shape
    F = [np.fft.rfft2(shot_rgb[:, :, c]) for c in range(3)]
    return {"H": H, "W": W, "F": F, "S": shot_rgb, "S2": [np.fft.rfft2(shot_rgb[:, :, c] ** 2) for c in range(3)]}

def match(prep, tmpl_rgba, scale):
    H, W = prep["H"], prep["W"]
    t = np.array(Image.fromarray(tmpl_rgba.astype(np.uint8)).resize(
        (max(4, round(tmpl_rgba.shape[1] * scale)), max(4, round(tmpl_rgba.shape[0] * scale))), Image.LANCZOS)).astype(np.float64)
    h, w = t.shape[:2]
    if h >= H or w >= W:
        return None
    a = t[:, :, 3] / 255.0
    T = t[:, :, :3] * a[:, :, None]
    n = a.sum()
    ST = T.sum((0, 1)); ST2 = (T * T).sum((0, 1))
    FA = np.fft.rfft2(a, s=(H, W))
    num = np.zeros((H - h + 1, W - w + 1))
    st2 = float((ST2 - ST * ST / n).sum())
    si2 = np.zeros_like(num)
    SI = np.zeros_like(num)
    for c in range(3):
        FT = np.fft.rfft2(T[:, :, c], s=(H, W))
        cc = np.fft.irfft2(prep["F"][c] * np.conj(FT), s=(H, W))[:H - h + 1, :W - w + 1]
        si = np.fft.irfft2(prep["F"][c] * np.conj(FA), s=(H, W))[:H - h + 1, :W - w + 1]
        s2 = np.fft.irfft2(prep["S2"][c] * np.conj(FA), s=(H, W))[:H - h + 1, :W - w + 1]
        num += cc - SI * 0 - ST[c] * si / n
        SI = si
        si2 += s2 - si * si / n
    return num / np.maximum(np.sqrt(max(st2, 1e-9) * np.maximum(si2, 1e-9)), 1e-9)
