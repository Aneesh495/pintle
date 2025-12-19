#!/usr/bin/env python3
"""
PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
File: tests/test_lz4_accelerator.py
Description: Verification of streaming line-rate LZ4 hardware decompression,
             token decoding, literal streaming, and match copy logic.

Author: Aneesh Krishna Parthasarathy
License: ISC License
"""

import unittest

class Lz4DecompressorModel:
    def __init__(self, history_size=4096):
        self.history_size = history_size
        self.history = bytearray(history_size)
        self.write_ptr = 0

    def decompress(self, compressed: bytes) -> bytes:
        out = bytearray()
        idx = 0
        n = len(compressed)

        while idx < n:
            token = compressed[idx]
            idx += 1

            lit_len = (token >> 4) & 0x0F
            match_len = (token & 0x0F) + 4

            # Extra literal length bytes
            if lit_len == 15:
                while idx < n:
                    extra = compressed[idx]
                    idx += 1
                    lit_len += extra
                    if extra != 255:
                        break

            # Copy literals
            for _ in range(lit_len):
                if idx < n:
                    b = compressed[idx]
                    idx += 1
                    out.append(b)
                    self.history[self.write_ptr % self.history_size] = b
                    self.write_ptr += 1

            if idx >= n:
                break # Reached end of stream

            # Read 16-bit offset
            offset = compressed[idx] | (compressed[idx + 1] << 8)
            idx += 2

            # Extra match length bytes
            if (token & 0x0F) == 15:
                while idx < n:
                    extra = compressed[idx]
                    idx += 1
                    match_len += extra
                    if extra != 255:
                        break

            # Copy match from circular history
            for _ in range(match_len):
                match_pos = (self.write_ptr - offset) % self.history_size
                b = self.history[match_pos]
                out.append(b)
                self.history[self.write_ptr % self.history_size] = b
                self.write_ptr += 1

        return bytes(out)

class TestLz4Accelerator(unittest.TestCase):
    def setUp(self):
        self.dec = Lz4DecompressorModel()

    def test_pure_literals(self):
        # 4 literals: "ABCD", no match
        # Token: lit_len=4, match_len=0 -> 0x40
        stream = bytes([0x40, ord('A'), ord('B'), ord('C'), ord('D')])
        out = self.dec.decompress(stream)
        self.assertEqual(out, b"ABCD")

    def test_literal_and_match_repetition(self):
        # "PINTLE" (6 literals) followed by match of length 12 at offset 6: "PINTLEPINTLEPINTLE"
        # Token: lit_len=6, match_len=(12 - 4) = 8 -> 0x68
        # Offset: 0x0006
        stream = bytes([0x68, ord('P'), ord('I'), ord('N'), ord('T'), ord('L'), ord('E'), 0x06, 0x00])
        out = self.dec.decompress(stream)
        self.assertEqual(out, b"PINTLEPINTLEPINTLE")

    def test_multi_token_sequence(self):
        # Sequence 1: 3 literals "FOO", match 4 offset 3 -> "FOOFOOF"
        # Sequence 2: 3 literals "BAR", no match -> "BAR"
        # Total: "FOOFOOFBAR"
        stream1 = bytes([0x30, ord('F'), ord('O'), ord('O'), 0x03, 0x00]) # lit=3, match=4
        stream2 = bytes([0x30, ord('B'), ord('A'), ord('R')])            # lit=3, end
        stream = stream1 + stream2

        out = self.dec.decompress(stream)
        self.assertEqual(out, b"FOOFOOFBAR")

if __name__ == "__main__":
    unittest.main()
