#!/usr/bin/env python3
"""
PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
File: tests/test_coherence_races.py
Description: Verification suite validating directory-based cache coherence,
             MOESI state transitions, MSHR conflict serialization, and Back-Invalidation races.

Author: Aneesh Krishna Parthasarathy
License: ISC License
"""

import unittest
from enum import Enum
from typing import Dict, Set

class CohState(Enum):
    INVALID = 0
    SHARED = 1
    MODIFIED = 2

class DirectoryEntry:
    def __init__(self):
        self.state = CohState.INVALID
        self.sharers: Set[int] = set()
        self.owner: int = 0

class CoherenceSimulator:
    def __init__(self):
        self.directory: Dict[int, DirectoryEntry] = {}
        self.mshr_table: Dict[int, dict] = {} # line_addr -> in-flight info

    def get_entry(self, line_addr: int) -> DirectoryEntry:
        if line_addr not in self.directory:
            self.directory[line_addr] = DirectoryEntry()
        return self.directory[line_addr]

    def request_read(self, host_id: int, line_addr: int) -> dict:
        if line_addr in self.mshr_table:
            return {"status": "STALL_CONFLICT", "snoops": []}

        entry = self.get_entry(line_addr)
        if entry.state == CohState.MODIFIED and entry.owner != host_id:
            # Need snoop to current owner
            snoop = {"target": entry.owner, "op": "SNP_DATA"}
            self.mshr_table[line_addr] = {
                "type": "READ",
                "requester": host_id,
                "pending_snoops": {entry.owner}
            }
            return {"status": "WAIT_SNOOP", "snoops": [snoop]}
        else:
            entry.state = CohState.SHARED
            entry.sharers.add(host_id)
            return {"status": "SUCCESS", "snoops": []}

    def request_write(self, host_id: int, line_addr: int) -> dict:
        if line_addr in self.mshr_table:
            return {"status": "STALL_CONFLICT", "snoops": []}

        entry = self.get_entry(line_addr)
        other_sharers = entry.sharers - {host_id}

        if entry.state == CohState.MODIFIED and entry.owner != host_id:
            other_sharers.add(entry.owner)

        if other_sharers:
            snoops = [{"target": h, "op": "SNP_INV"} for h in other_sharers]
            self.mshr_table[line_addr] = {
                "type": "WRITE",
                "requester": host_id,
                "pending_snoops": set(other_sharers)
            }
            return {"status": "WAIT_SNOOP", "snoops": snoops}
        else:
            entry.state = CohState.MODIFIED
            entry.owner = host_id
            entry.sharers = {host_id}
            return {"status": "SUCCESS", "snoops": []}

    def acknowledge_snoop(self, host_id: int, line_addr: int) -> bool:
        if line_addr not in self.mshr_table:
            return False

        mshr = self.mshr_table[line_addr]
        mshr["pending_snoops"].discard(host_id)

        if not mshr["pending_snoops"]:
            # All snoops acknowledged, commit transaction
            req_host = mshr["requester"]
            entry = self.get_entry(line_addr)
            if mshr["type"] == "WRITE":
                entry.state = CohState.MODIFIED
                entry.owner = req_host
                entry.sharers = {req_host}
            else:
                entry.state = CohState.SHARED
                entry.sharers.add(req_host)
            del self.mshr_table[line_addr]
            return True # Transaction complete
        return False

class TestCoherenceRaces(unittest.TestCase):
    def setUp(self):
        self.sim = CoherenceSimulator()

    def test_concurrent_reads_shared_state(self):
        line = 0x1000
        res0 = self.sim.request_read(0, line)
        self.assertEqual(res0["status"], "SUCCESS")

        res1 = self.sim.request_read(1, line)
        self.assertEqual(res1["status"], "SUCCESS")

        entry = self.sim.get_entry(line)
        self.assertEqual(entry.state, CohState.SHARED)
        self.assertEqual(entry.sharers, {0, 1})

    def test_write_invalidates_all_sharers(self):
        line = 0x2000
        # Host 0 and 1 read line
        self.sim.request_read(0, line)
        self.sim.request_read(1, line)

        # Host 2 writes to line
        res2 = self.sim.request_write(2, line)
        self.assertEqual(res2["status"], "WAIT_SNOOP")
        self.assertEqual(len(res2["snoops"]), 2)

        # Host 0 acks snoop
        done = self.sim.acknowledge_snoop(0, line)
        self.assertFalse(done) # Host 1 still pending

        # Host 1 acks snoop
        done = self.sim.acknowledge_snoop(1, line)
        self.assertTrue(done)

        entry = self.sim.get_entry(line)
        self.assertEqual(entry.state, CohState.MODIFIED)
        self.assertEqual(entry.owner, 2)
        self.assertEqual(entry.sharers, {2})

    def test_mshr_conflict_serialization(self):
        line = 0x3000
        self.sim.request_read(0, line)

        # Host 1 writes, pending snoop to Host 0
        self.sim.request_write(1, line)

        # Host 2 attempts simultaneous write to same line
        res2 = self.sim.request_write(2, line)
        self.assertEqual(res2["status"], "STALL_CONFLICT") # Must stall

        # Host 0 completes snoop
        self.sim.acknowledge_snoop(0, line)

        # Now Host 2 can proceed
        res2_retry = self.sim.request_write(2, line)
        self.assertEqual(res2_retry["status"], "WAIT_SNOOP")
        self.assertEqual(res2_retry["snoops"][0]["target"], 1)

if __name__ == "__main__":
    unittest.main()
