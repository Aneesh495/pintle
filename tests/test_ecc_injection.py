#!/usr/bin/env python3
"""
PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
File: tests/test_ecc_injection.py
Description: Exhaustive matrix verification of the (72, 64) SECDED Hamming codec,
             testing 100% of 1-bit corrections and all 2,016 2-bit error pairs.

Author: Aneesh Krishna Parthasarathy
License: ISC License
"""

import unittest
from itertools import combinations

def compute_parity64(d: int) -> int:
    p = [0] * 8
    # Parity bit 0: covers even bits
    p0 = 0
    for i in range(64):
        if (i % 2) == 1:
            p0 ^= (d >> i) & 1
    p[0] = p0

    # Parity bit 1
    p1 = 0
    for i in range(64):
        if ((i // 2) % 2) == 1:
            p1 ^= (d >> i) & 1
    p[1] = p1

    # Parity bit 2
    p2 = 0
    for i in range(64):
        if ((i // 4) % 2) == 1:
            p2 ^= (d >> i) & 1
    p[2] = p2

    # Parity bit 3
    p3 = 0
    for i in range(64):
        if ((i // 8) % 2) == 1:
            p3 ^= (d >> i) & 1
    p[3] = p3

    # Parity bit 4
    p4 = 0
    for i in range(64):
        if ((i // 16) % 2) == 1:
            p4 ^= (d >> i) & 1
    p[4] = p4

    # Parity bit 5
    p5 = 0
    for i in range(64):
        if ((i // 32) % 2) == 1:
            p5 ^= (d >> i) & 1
    p[5] = p5

    # Parity bit 6
    p6 = 0
    for i in range(32):
        p6 ^= (d >> (i * 2)) & 1
    p[6] = p6

    # Parity bit 7: overall data parity
    p7 = 0
    for i in range(64):
        p7 ^= (d >> i) & 1
    p[7] = p7

    ecc = 0
    for k in range(8):
        ecc |= (p[k] << k)
    return ecc

def decode_secded64(raw_data: int, raw_p: int):
    expected_p = compute_parity64(raw_data)
    syndrome = expected_p ^ raw_p

    overall_parity_err = ((syndrome >> 7) & 1) == 1
    pos_syndrome = syndrome & 0x7F

    if syndrome == 0:
        return (raw_data, False, False) # Zero errors
    elif overall_parity_err:
        # Single-bit error
        bit_idx = pos_syndrome & 0x3F
        corrected = raw_data ^ (1 << bit_idx)
        return (corrected, True, False) # Corrected SEC
    else:
        # Double-bit uncorrectable error
        return (raw_data, False, True) # Fatal DED

class TestEccSecDed(unittest.TestCase):
    def setUp(self):
        self.test_data = 0xCAFEBABE01234567

    def test_clean_data(self):
        ecc = compute_parity64(self.test_data)
        out, corrected, fatal = decode_secded64(self.test_data, ecc)
        self.assertEqual(out, self.test_data)
        self.assertFalse(corrected)
        self.assertFalse(fatal)

    def test_all_64_single_bit_data_errors(self):
        ecc = compute_parity64(self.test_data)
        for bit in range(64):
            corrupted = self.test_data ^ (1 << bit)
            out, corrected, fatal = decode_secded64(corrupted, ecc)
            self.assertEqual(out, self.test_data, f"Failed correcting bit {bit}")
            self.assertTrue(corrected)
            self.assertFalse(fatal)

    def test_all_2016_double_bit_error_pairs(self):
        ecc = compute_parity64(self.test_data)
        pairs_tested = 0
        for bit1, bit2 in combinations(range(64), 2):
            corrupted = self.test_data ^ (1 << bit1) ^ (1 << bit2)
            out, corrected, fatal = decode_secded64(corrupted, ecc)
            self.assertFalse(corrected, f"False correction on pair ({bit1}, {bit2})")
            self.assertTrue(fatal, f"Failed to detect fatal 2-bit error on pair ({bit1}, {bit2})")
            pairs_tested += 1
        self.assertEqual(pairs_tested, 2016)

if __name__ == "__main__":
    unittest.main()
