#!/bin/bash

echo "=== Testing AES-128 Bruteforce with Small Search Space ==="
echo ""
echo "This test uses a known key and searches only the last 2 bytes (65,536 keys)"
echo ""

# Known key: 2b7e151628aed2a6abf7158809cf4f3c
# We will pretend we only know the first 14 bytes: 2b7e151628aed2a6abf7158809cf
# And search for the last 2 bytes: 4f3c

# First, generate test plaintext/ciphertext with the known key
PLAINTEXT="00112233445566778899aabbccddeeff"

# Use Python to encrypt with the known key
python3 << 'PYTHON_EOF'
from Crypto.Cipher import AES
import binascii

key = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
plaintext = bytes.fromhex("00112233445566778899aabbccddeeff")

cipher = AES.new(key, AES.MODE_ECB)
ciphertext = cipher.encrypt(plaintext)

print(f"Key:        {key.hex()}")
print(f"Plaintext:  {plaintext.hex()}")
print(f"Ciphertext: {ciphertext.hex()}")
print(f"\nSearching for last 2 bytes (4f3c) with known prefix (2b7e151628aed2a6abf7158809cf)...")

# Save to file for the C program
with open('/tmp/test_bruteforce_params.txt', 'w') as f:
    f.write(f"{plaintext.hex()}\n")
    f.write(f"{ciphertext.hex()}\n")
    f.write("2b7e151628aed2a6abf7158809cf\n")  # 14 bytes known
PYTHON_EOF

# Read the parameters
PARAMS=$(cat /tmp/test_bruteforce_params.txt)
PLAINTEXT=$(echo "$PARAMS" | sed -n '1p')
CIPHERTEXT=$(echo "$PARAMS" | sed -n '2p')
KNOWN_PREFIX=$(echo "$PARAMS" | sed -n '3p')

echo ""
echo "Running bruteforce..."
./build/cuda-aes-bruteforce "$PLAINTEXT" "$CIPHERTEXT" "$KNOWN_PREFIX"
