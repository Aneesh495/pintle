#!/usr/bin/env python3
"""
PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
File: tests/test_flit_codec.py
Description: Python test suite verifying CXL 3.1 256-byte Standard Flit
             packing, unpacking, slot alignment, and Castagnoli CRC-32C integrity.

Author: Aneesh Krishna Parthasarathy
License: ISC License
"""

import struct
import unittest

CRC32C_POLYNOMIAL = 0x82F63B78

def compute_crc32c(data: bytes) -> int:
    crc = 0xFFFFFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ CRC32C_POLYNOMIAL
            else:
                crc >>= 1
    return (~crc) & 0xFFFFFFFF

class CxlStandardFlit:
    def __init__(self, flit_type=0xC3, seq_num=0, ack_num=0, credit_tokens=0):
        self.flit_type = flit_type
        self.seq_num = seq_num
        self.ack_num = ack_num
        self.credit_tokens = credit_tokens
        self.slots = [bytearray(16) for _ in range(14)]
        self.crc = 0

    def serialize(self) -> bytes:
        header = struct.pack("BBBB", self.flit_type, self.seq_num, self.ack_num, self.credit_tokens)
        slots_bytes = b"".join(self.slots)
        crc_data = header + slots_bytes
        self.crc = compute_crc32c(crc_data)
        return crc_data + struct.pack("<I", self.crc)

    @classmethod
    def deserialize(cls, raw: bytes):
        if len(raw) != 256:
            raise ValueError(f"Flit size must be exactly 256 bytes, got {len(raw)}")
        flit_type, seq_num, ack_num, credit_tokens = struct.unpack("BBBB", raw[:4])
        slots_data = raw[4:228]
        expected_crc = struct.unpack("<I", raw[228:232])[0]

        calc_crc = compute_crc32c(raw[:228])
        if calc_crc != expected_crc:
            raise ValueError(f"CRC-32C mismatch: calculated 0x{calc_crc:08X}, expected 0x{expected_crc:08X}")

        flit = cls(flit_type, seq_num, ack_num, credit_tokens)
        flit.slots = [bytearray(slots_data[i*16:(i+1)*16]) for i in range(14)]
        flit.crc = expected_crc
        return flit

class TestFlitCodec(unittest.TestCase):
    def test_crc32c_castagnoli_known_vector(self):
        # Known test string "123456789"
        test_str = b"123456789"
        expected_crc = 0xE3069283
        self.assertEqual(compute_crc32c(test_str), expected_crc)

    def test_flit_roundtrip_clean(self):
        flit = CxlStandardFlit(flit_type=0xC3, seq_num=42, ack_num=18, credit_tokens=15)
        # Populate slot 0 with request metadata
        flit.slots[0][0] = 0x01 # host 1
        flit.slots[0][1] = 0x02 # read op
        # Populate slots 1..4 with 64-byte pattern
        for s in range(1, 5):
            for b in range(16):
                flit.slots[s][b] = (s * 16 + b) & 0xFF

        serialized = flit.serialize()
        self.assertEqual(len(serialized), 232) # 228 + 4 CRC

        deserialized = CxlStandardFlit.deserialize(serialized + bytes(256 - len(serialized)))
        self.assertEqual(deserialized.flit_type, 0xC3)
        self.assertEqual(deserialized.seq_num, 42)
        self.assertEqual(deserialized.ack_num, 18)
        self.assertEqual(deserialized.credit_tokens, 15)
        self.assertEqual(deserialized.slots[1][0], 16)

    def test_flit_crc_corruption_detection(self):
        flit = CxlStandardFlit(flit_type=0xC3, seq_num=1, ack_num=0, credit_tokens=4)
        raw = bytearray(flit.serialize() + bytes(256 - 232))

        # Inject 1-bit corruption in payload slot 2
        raw[35] ^= 0x01

        with self.assertRaises(ValueError):
            CxlStandardFlit.deserialize(bytes(raw))

if __name__ == "__main__":
    unittest.main()
