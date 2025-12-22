#!/usr/bin/env python3
"""
Generate a test case for AES bruteforce with small search space
"""
from Crypto.Cipher import AES
import sys

# Known full key
full_key = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
plaintext = bytes.fromhex("00112233445566778899aabbccddeeff")

# Encrypt
cipher = AES.new(full_key, AES.MODE_ECB)
ciphertext = cipher.encrypt(plaintext)

print("=== AES-128 Bruteforce Test Case ===\n")
print(f"Full key:   {full_key.hex()}")
print(f"Plaintext:  {plaintext.hex()}")
print(f"Ciphertext: {ciphertext.hex()}")
print()
print("Known key prefix (12 bytes): 2b7e151628aed2a6abf71588")
print("Target suffix (4 bytes):     09cf4f3c")
print()
print("To run the bruteforce:")
print(f"./build/cuda-aes-bruteforce {plaintext.hex()} {ciphertext.hex()} 2b7e151628aed2a6abf71588")
print()
print("Expected result: The program should find the key 2b7e151628aed2a6abf7158809cf4f3c")
print(f"Search space: 2^32 = 4,294,967,296 keys (approximately 1 hour on a single A100 at 1 Gkeys/s)")
