#!/usr/bin/env python3
"""
PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
File: tests/test_multi_host_pbr.py
Description: Verification of Port-Based Routing (PBR), multi-tenant memory partition
             isolation, and 4-way round-robin crossbar arbitration fairness.

Author: Aneesh Krishna Parthasarathy
License: ISC License
"""

import unittest
from typing import Optional

class HostPartition:
    def __init__(self, base_addr: int, limit_addr: int, write_permitted: bool):
        self.base_addr = base_addr
        self.limit_addr = limit_addr
        self.write_permitted = write_permitted

class PortBasedRouterModel:
    def __init__(self):
        self.partitions = {}

    def set_partition(self, host_id: int, base_addr: int, limit_addr: int, write_perm: bool):
        self.partitions[host_id] = HostPartition(base_addr, limit_addr, write_perm)

    def route_request(self, host_id: int, addr: int, is_write: bool) -> Optional[int]:
        if host_id not in self.partitions:
            return None

        part = self.partitions[host_id]
        if not (part.base_addr <= addr <= part.limit_addr):
            return None # Out of bounds violation!

        if is_write and not part.write_permitted:
            return None # Read-only violation!

        # Address decode: channel = addr[7:6]
        channel = (addr >> 6) & 0x03
        return channel

class RoundRobinArbiter4Model:
    def __init__(self):
        self.last_grant = 3

    def arbitrate(self, requests: list) -> int:
        # requests is a list of 4 bools [req0, req1, req2, req3]
        for offset in range(1, 5):
            idx = (self.last_grant + offset) % 4
            if requests[idx]:
                self.last_grant = idx
                return idx
        return -1 # No request

class TestMultiHostPbr(unittest.TestCase):
    def setUp(self):
        self.pbr = PortBasedRouterModel()
        # Host 0: 0x0000_0000 - 0x0000_FFFF (R/W)
        self.pbr.set_partition(0, 0x00000000, 0x0000FFFF, True)
        # Host 1: 0x0001_0000 - 0x0001_FFFF (Read-only)
        self.pbr.set_partition(1, 0x00010000, 0x0001FFFF, False)

    def test_in_bounds_routing(self):
        # Channel = (0x00000040 >> 6) & 3 = 1
        ch = self.pbr.route_request(0, 0x00000040, is_write=False)
        self.assertEqual(ch, 1)

        # Channel = (0x00000080 >> 6) & 3 = 2
        ch = self.pbr.route_request(0, 0x00000080, is_write=True)
        self.assertEqual(ch, 2)

    def test_out_of_bounds_isolation(self):
        # Host 0 attempting access to Host 1 partition
        ch = self.pbr.route_request(0, 0x00010040, is_write=False)
        self.assertIsNone(ch) # Dropped by partition isolation

    def test_read_only_isolation(self):
        # Host 1 read permitted
        ch = self.pbr.route_request(1, 0x00010040, is_write=False)
        self.assertIsNotNone(ch)

        # Host 1 write rejected
        ch = self.pbr.route_request(1, 0x00010040, is_write=True)
        self.assertIsNone(ch)

    def test_arbiter_fairness_full_contention(self):
        arb = RoundRobinArbiter4Model()
        # All 4 ports requesting simultaneously
        all_reqs = [True, True, True, True]

        grants = []
        for _ in range(8):
            grants.append(arb.arbitrate(all_reqs))

        # Expected perfect round-robin: 0, 1, 2, 3, 0, 1, 2, 3
        self.assertEqual(grants, [0, 1, 2, 3, 0, 1, 2, 3])

if __name__ == "__main__":
    unittest.main()
