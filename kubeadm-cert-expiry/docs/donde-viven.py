"""Diagrama: dónde vive cada certificado en un cluster kubeadm (control plane vs worker).

Regenerar (parado en la raíz del workshop) con:
    python3 docs/donde-viven.py
    rsvg-convert -z 2 docs/donde-viven.svg -o docs/donde-viven.png

Solo usa la biblioteca estándar. Los colores codifican el ciclo de vida del certificado.
"""

from pathlib import Path
from xml.sax.saxutils import escape

W, H = 1200, 966
SANS = "Inter, 'Helvetica Neue', Arial, 'DejaVu Sans', sans-serif"
MONO = "'JetBrains Mono', Menlo, Consolas, 'DejaVu Sans Mono', monospace"

INK, SOFT, FAINT, LINE = "#16202a", "#4a5662", "#7b8794", "#cfd6dd"

# Ciclo de vida -> (relleno, borde, texto)
KIND = {
    "renew":   ("#fff3dc", "#d98a00", "#6b4200"),  # 1 año, kubeadm certs renew
    "ca":      ("#f0ebff", "#7656d6", "#3b2689"),  # CA, 10 años
    "rota":    ("#e3f5ea", "#2f9e5b", "#1b5e37"),  # el kubelet lo rota solo
    "quieto":  ("#eef1f4", "#98a3ae", "#46505a"),  # no vence / nadie lo valida
    "neutral": ("#ffffff", "#bcc5ce", "#16202a"),  # no es un certificado
}

out: list[str] = []


def text(x, y, s, size=13, color=INK, weight=400, family=SANS, anchor="start", italic=False):
    style = ' font-style="italic"' if italic else ""
    out.append(
        f'<text x="{x}" y="{y}" xml:space="preserve" font-family="{family}" font-size="{size}" '
        f'fill="{color}" font-weight="{weight}" text-anchor="{anchor}"{style}>{escape(s)}</text>'
    )


def rect(x, y, w, h, fill, stroke, rx=10, dash=False, sw=1.2):
    d = ' stroke-dasharray="5 4"' if dash else ""
    out.append(
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" '
        f'stroke="{stroke}" stroke-width="{sw}"{d}/>'
    )


def chip_w(label, size=12.5):
    return round(len(label) * size * 0.61 + 20)


def chip(x, y, label, kind, w=None):
    fill, stroke, ink = KIND[kind]
    w = w or chip_w(label)
    rect(x, y, w, 26, fill, stroke, rx=6)
    text(x + 10, y + 17.5, label, size=12.5, color=ink, family=MONO)
    return w


def path_header(x, y, p, note=None):
    text(x, y, p, size=14, weight=700, family=MONO)
    if note:
        text(x + chip_w(p, 14) - 6, y, note, size=12.5, color=FAINT)


def panel(x, y, w, h, title, sub):
    rect(x, y, w, h, "#f7f8fa", "#c3ccd5", rx=16, sw=1.5)
    text(x + 22, y + 34, title, size=17, weight=800)
    text(x + 22 + len(title) * 12.6 + 12, y + 34, sub, size=13, color=SOFT)


def section(x, y, w, h):
    rect(x, y, w, h, "#ffffff", LINE, rx=12)


# ---------------------------------------------------------------- título
text(32, 46, "Dónde vive cada certificado en un cluster kubeadm", size=25, weight=800)
text(32, 72, "Valores por defecto de kubeadm. Cada control plane tiene su propia copia de todo lo de la izquierda.",
     size=14, color=SOFT)

# ---------------------------------------------------------------- control plane
CPX, CPY, CPW = 32, 96, 776
MANI_H = 150
CPH = 54 + 300 + 14 + 104 + 14 + MANI_H + 18
panel(CPX, CPY, CPW, CPH, "CONTROL PLANE", "× 3 nodos")

# /etc/kubernetes/pki
sx, sy, sw_, sh = CPX + 18, CPY + 54, CPW - 36, 300
section(sx, sy, sw_, sh)
path_header(sx + 18, sy + 30, "/etc/kubernetes/pki/")

c1, c2, c3 = sx + 18, sx + 262, sx + 538
text(c1, sy + 62, "Autoridades (CA)", size=13, weight=700)
text(c1, sy + 80, "10 años · kubeadm no las rota", size=12, color=FAINT)
for i, s in enumerate(["ca.crt · ca.key", "etcd/ca.crt · ca.key", "front-proxy-ca.crt · .key"]):
    chip(c1, sy + 94 + i * 34, s, "ca", w=226)

text(c2, sy + 62, "Certificados hoja", size=13, weight=700)
text(c2, sy + 80, "1 año · kubeadm certs renew", size=12, color=FAINT)
for i, s in enumerate([
    "apiserver.crt",
    "apiserver-kubelet-client.crt",
    "apiserver-etcd-client.crt",
    "front-proxy-client.crt",
    "etcd/server.crt",
    "etcd/peer.crt",
    "etcd/healthcheck-client.crt",
]):
    chip(c2, sy + 94 + i * 28.5, s, "renew", w=258)

text(c3, sy + 62, "ServiceAccounts", size=13, weight=700)
text(c3, sy + 80, "par de claves, no vence", size=12, color=FAINT)
chip(c3, sy + 94, "sa.key · sa.pub", "quieto", w=168)

# /etc/kubernetes/*.conf
ky = sy + sh + 14
section(sx, ky, sw_, 104)
path_header(sx + 18, ky + 30, "/etc/kubernetes/*.conf", "kubeconfigs con el certificado embebido en base64")
cx = sx + 18
for s in ["admin.conf", "super-admin.conf*", "controller-manager.conf", "scheduler.conf"]:
    cx += chip(cx, ky + 44, s, "renew") + 10
text(sx + 18, ky + 90, "1 año · kubeadm certs renew      * solo en el nodo donde se corrió kubeadm init",
     size=12, color=FAINT)

# manifests + kubelet
my = ky + 104 + 14
half = (sw_ - 14) / 2
section(sx, my, half, MANI_H)
path_header(sx + 18, my + 30, "/etc/kubernetes/manifests/")
for i, s in enumerate(["kube-apiserver", "kube-controller-manager", "kube-scheduler", "etcd"]):
    col, row = i % 2, i // 2
    chip(sx + 18 + col * 140, my + 44 + row * 32, s, "neutral", w=130 if col == 0 else 192)
text(sx + 18, my + 122, "Static pods: leen los certificados al arrancar.", size=12, color=FAINT)
text(sx + 18, my + 140, "Tras renovar: reiniciarlos, de a un nodo.", size=12.5, color="#9a3412", weight=700)

kx = sx + half + 14
section(kx, my, half, MANI_H)
path_header(kx + 18, my + 30, "/var/lib/kubelet/pki/", "igual que en el worker")
chip(kx + 18, my + 44, "kubelet-client-current.pem", "rota")
chip(kx + 18, my + 76, "kubelet.crt", "quieto")
text(kx + 18, my + 122, "kubelet.conf apunta al primero.", size=12, color=FAINT)
text(kx + 18, my + 140, "Existe en todos los nodos.", size=12, color=FAINT)

# ---------------------------------------------------------------- worker
WX, WY, WW, WH = 826, 96, 342, CPH
panel(WX, WY, WW, WH, "WORKER", "× N nodos")

wsx, wsw = WX + 18, WW - 36
s1 = WY + 54
section(wsx, s1, wsw, 92)
path_header(wsx + 18, s1 + 30, "/etc/kubernetes/")
chip(wsx + 18, s1 + 46, "pki/ca.crt", "ca")
chip(wsx + 136, s1 + 46, "kubelet.conf", "neutral")

s2 = s1 + 92 + 14
section(wsx, s2, wsw, 206)
path_header(wsx + 18, s2 + 30, "/var/lib/kubelet/pki/")
chip(wsx + 18, s2 + 46, "kubelet-client-current.pem", "rota")
text(wsx + 18, s2 + 92, "Cliente: el kubelet pide uno nuevo", size=12.5, color=SOFT)
text(wsx + 18, s2 + 110, "con 30 %–10 % de vida restante.", size=12.5, color=SOFT)
chip(wsx + 18, s2 + 128, "kubelet.crt", "quieto")
text(wsx + 18, s2 + 174, "Serving autofirmado: 1 año, no rota", size=12.5, color=SOFT)
text(wsx + 18, s2 + 190, "y por defecto nadie lo valida.", size=12.5, color=SOFT)

s3 = s2 + 206 + 14
rect(wsx, s3, wsw, WY + WH - 18 - s3, "#fbfcfd", "#98a3ae", rx=12, dash=True)
text(wsx + 18, s3 + 34, "Nada de kubeadm que renovar.", size=15, weight=800)
text(wsx + 18, s3 + 60, "Solo la CA pública (sin la clave)", size=12.5, color=SOFT)
text(wsx + 18, s3 + 78, "y los certificados del kubelet.", size=12.5, color=SOFT)
text(wsx + 18, s3 + 106, "kubeadm certs check-expiration", size=12.5, family=MONO, color=INK)
text(wsx + 18, s3 + 124, "falla acá: busca apiserver.key", size=12.5, color=SOFT)
text(wsx + 18, s3 + 142, "y no la encuentra.", size=12.5, color=SOFT)
text(wsx + 18, s3 + 178, "Si el kubelet no logra rotar:", size=12.5, color=SOFT)
text(wsx + 18, s3 + 198, "kubectl get csr", size=12.5, family=MONO, color=INK)
text(wsx + 18, s3 + 216, "y revisar las que quedaron Pending.", size=12.5, color=SOFT)

# ---------------------------------------------------------------- leyenda y comandos
ly = CPY + CPH + 26
legend = [
    ("renew", "1 año: los lista check-expiration y los renueva kubeadm certs renew"),
    ("ca", "CA, 10 años: check-expiration la muestra, renew no la toca"),
    ("rota", "Rota solo: kubeadm no lo lista"),
    ("quieto", "No vence, o nadie lo valida"),
]
for i, (k, label) in enumerate(legend):
    col, row = i % 2, i // 2
    x = 32 + col * 520
    y = ly + row * 28
    fill, stroke, _ = KIND[k]
    rect(x, y, 22, 16, fill, stroke, rx=4)
    text(x + 32, y + 13, label, size=13, color=SOFT)

by = ly + 70
rect(32, by, 590, 92, "#16202a", "#16202a", rx=10)
text(50, by + 26, "En cada control plane, de a uno", size=12.5, color="#9fb3c8", weight=700)
text(50, by + 50, "sudo kubeadm certs check-expiration", size=13, color="#e8f1f8", family=MONO)
text(50, by + 72, "sudo kubeadm certs renew all   # + reiniciar static pods", size=13, color="#e8f1f8", family=MONO)

rect(640, by, 528, 92, "#16202a", "#16202a", rx=10)
text(658, by + 26, "En cualquier nodo (kubelet)", size=12.5, color="#9fb3c8", weight=700)
text(658, by + 50, "sudo openssl x509 -noout -enddate \\", size=13, color="#e8f1f8", family=MONO)
text(658, by + 72, "  -in /var/lib/kubelet/pki/kubelet-client-current.pem", size=13, color="#e8f1f8", family=MONO)

svg = (
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
    f'<rect width="{W}" height="{H}" fill="#ffffff"/>' + "".join(out) + "</svg>\n"
)
Path(__file__).with_suffix(".svg").write_text(svg, encoding="utf-8")
print(f"ok: {Path(__file__).with_suffix('.svg')}")
