#!/usr/bin/env python3
"""Stable, project-local signing identity. Never alters system certificate trust."""
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
identity_dir = root / '.local-signing'
identity_dir.mkdir(mode=0o700, exist_ok=True)
os.chmod(identity_dir, 0o700)
key = identity_dir / 'MacDuo.key.pem'
cert = identity_dir / 'MacDuo.cert.pem'

def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, **kwargs)

if not key.exists() or not cert.exists():
    run(['openssl', 'req', '-x509', '-newkey', 'rsa:3072', '-nodes', '-sha256',
         '-days', '3650', '-subj', '/CN=MacDuo Local Development/',
         '-addext', 'basicConstraints=critical,CA:FALSE',
         '-addext', 'keyUsage=critical,digitalSignature',
         '-addext', 'extendedKeyUsage=critical,codeSigning',
         '-keyout', str(key), '-out', str(cert)])
    os.chmod(key, 0o600)
    os.chmod(cert, 0o600)
helper = root / '.build/local-sign'
source = root / 'scripts/local_sign.m'
if not helper.exists() or helper.stat().st_mtime < source.stat().st_mtime:
    helper.parent.mkdir(exist_ok=True)
    run(['clang', '-fobjc-arc', str(source), '-framework', 'Foundation', '-framework', 'Security', '-o', str(helper)])
with tempfile.TemporaryDirectory(prefix='macduo-sign-') as temporary:
    archive = str(Path(temporary) / 'identity.p12')
    env = dict(os.environ, MACDUO_P12_PASSWORD=secrets.token_urlsafe(32))
    try:
        run(['openssl', 'pkcs12', '-export', '-legacy', '-inkey', str(key), '-in', str(cert),
             '-out', archive, '-passout', 'env:MACDUO_P12_PASSWORD'], env=env)
        result = run([str(helper), str(Path(sys.argv[1]).resolve()), archive], env=env)
        if result.stderr: print(result.stderr.decode().strip())
        run(['codesign', '--verify', '--strict', sys.argv[1]])
        print('Signed with stable project-local MacDuo identity; system trust unchanged.')
    except subprocess.CalledProcessError as error:
        print(error.stderr.decode(), file=sys.stderr)
        sys.exit(1)
