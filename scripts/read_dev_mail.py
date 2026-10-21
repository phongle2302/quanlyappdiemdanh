#!/usr/bin/env python3
"""Read the latest locally delivered development email. Never use in production."""
from email import policy
from email.parser import BytesParser
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
folder = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'server/Attendance.Api/App_Data/mail'
files = sorted(folder.glob('*.eml'), key=lambda p: p.stat().st_mtime, reverse=True)
if not files:
    sys.exit('Chưa có email thử nghiệm. Gửi yêu cầu đăng ký/đăng nhập trước.')
msg = BytesParser(policy=policy.default).parsebytes(files[0].read_bytes())
print(f'Đến: {msg["To"]}\nTiêu đề: {msg["Subject"]}\n')
body = msg.get_body(preferencelist=('plain',)) if msg.is_multipart() else msg
print(body.get_content())
