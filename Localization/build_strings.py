#!/usr/bin/env python3
"""VitalMac yerelleştirme dosyalarını üretir ve doğrular.

Kullanım:
  python3 Localization/build_strings.py [--keys <keys.json>]

- Localization/en.py tablosundan en.lproj/Localizable.strings üretir.
- tr.lproj/Localizable.strings boş kalır (anahtarlar zaten Türkçe).
- Her değerde biçim belirteçlerinin (%@, %lld, %d, %%) anahtarla aynı olduğunu denetler.
- --keys verilirse (derleyicinin çıkardığı anahtar listesi), Türkçe harf ya da sözcük içeren
  ama tabloda karşılığı olmayan anahtarları raporlar ve hata koduyla çıkar.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from en import EN  # noqa: E402

SPEC = re.compile(r"%(?:%|@|lld|ld|d|\.\d+f|f)")
TURKISH = re.compile(r"[çğıöşüÇĞİÖŞÜ]|\b(?:dosya|öğe|uygulama|Panel|Disk|Ağ|Pil|Fan|Kapat|Sil|Yenile|Tümü|Kalem|Yapı)\b")


def escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main() -> int:
    errors = []
    for k, v in EN.items():
        if sorted(SPEC.findall(k)) != sorted(SPEC.findall(v)):
            errors.append(f"biçim belirteci uyuşmuyor: {k!r} → {v!r}")

    if "--keys" in sys.argv:
        keys = json.load(open(sys.argv[sys.argv.index("--keys") + 1], encoding="utf-8"))
        missing = [k for k in keys if TURKISH.search(k) and k not in EN]
        errors += [f"çevirisi yok: {k!r}" for k in missing]
        unused = [k for k in EN if k not in keys]
        if unused:
            print(f"uyarı: kodda artık geçmeyen {len(unused)} anahtar:", *map(repr, unused[:10]), sep="\n  ")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    for lang, table in (("en", EN), ("tr", {})):
        d = os.path.join(HERE, f"{lang}.lproj")
        os.makedirs(d, exist_ok=True)
        lines = [f'"{escape(k)}" = "{escape(v)}";' for k, v in sorted(table.items())]
        with open(os.path.join(d, "Localizable.strings"), "w", encoding="utf-8") as f:
            f.write("/* VitalMac — Localization/build_strings.py ile üretildi; elle düzenlemeyin. */\n")
            f.write("\n".join(lines) + "\n")
    with open(os.path.join(HERE, "en.lproj", "InfoPlist.strings"), "w", encoding="utf-8") as f:
        f.write('"NSAppleEventsUsageDescription" = "Administrator tasks such as freeing memory open the system password prompt, and Empty Trash asks Finder to empty it.";\n')
    with open(os.path.join(HERE, "tr.lproj", "InfoPlist.strings"), "w", encoding="utf-8") as f:
        f.write('"NSAppleEventsUsageDescription" = "Bellek temizleme gibi yönetici işlemleri için sistem şifre penceresi açılır; Çöpü Boşalt, Finder\'dan çöpü boşaltmasını ister.";\n')
    print(f"tamam: en {len(EN)} çeviri, tr (kaynak dil)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
