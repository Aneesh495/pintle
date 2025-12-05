/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: sim/main_cosim.cpp
 * Description: Standalone multi-host CXL 3.1 co-simulation harness and stress test
 *              exercising concurrent multi-host reads, writes, and Back-Invalidations.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

#include "cxl_packet.hpp"
#include "cxl_host_agent.hpp"
#include "cxl_monitor.hpp"

#include <iostream>
#include <vector>
#include <random>
#include <cassert>

int main(int argc, char* argv[]) {
    std::cout << "=================================================================\n";
    std::cout << "PINTLE: CXL 3.1 Co-Simulation Harness & Protocol Stress Runner\n";
    std::cout << "=================================================================\n";

    pintle::CxlMonitor monitor;

    // Instantiate 4 Host Agents
    std::vector<std::unique_ptr<pintle::CxlHostAgent>> hosts;
    for (uint8_t h = 0; h < 4; ++h) {
        hosts.push_back(std::make_unique<pintle::CxlHostAgent>(h, h));
    }

    std::mt19937_64 rng(1337);
    std::uniform_int_distribution<uint64_t> addr_dist(0, 127); // 128 cache lines
    std::uniform_int_distribution<int> host_dist(0, 3);
    std::uniform_int_distribution<int> op_dist(0, 1); // 0 = read, 1 = write

    // Simulated Central Memory Pool Backing Store
    std::unordered_map<uint64_t, std::array<uint8_t, pintle::CACHELINE_BYTES>> memory_pool;

    uint64_t sim_cycles = 2500;
    size_t transactions_issued = 0;

    std::cout << "[Runner] Launching synthetic multi-host stress across "
              << sim_cycles << " simulation cycles...\n";

    for (uint64_t cycle = 0; cycle < sim_cycles; ++cycle) {
        // Issue transaction every few cycles
        if (cycle % 3 == 0) {
            uint8_t h_idx = host_dist(rng);
            uint64_t line_addr = addr_dist(rng) * 64;
            int op_type = op_dist(rng);

            if (op_type == 0) {
                // Read Request
                auto req = hosts[h_idx]->issueRead(line_addr);
                monitor.onRequestDispatched(req, cycle);

                // Service Read from pool
                pintle::CxlMemResponse rsp;
                rsp.host_id = req.host_id;
                rsp.port_id = req.port_id;
                rsp.tag = req.tag;
                rsp.status = pintle::CxlRspStatus::RSP_DATA_READY;
                rsp.has_data = true;

                if (memory_pool.find(line_addr) == memory_pool.end()) {
                    rsp.data.fill(0x5A);
                } else {
                    rsp.data = memory_pool[line_addr];
                }

                hosts[h_idx]->handleResponse(rsp);
                monitor.onResponseReceived(rsp, cycle + 12);
                transactions_issued++;
            } else {
                // Write Request
                std::array<uint8_t, pintle::CACHELINE_BYTES> wr_payload;
                wr_payload.fill(static_cast<uint8_t>((cycle + h_idx) & 0xFF));

                auto req = hosts[h_idx]->issueWrite(line_addr, wr_payload);

                // Snoops to peer hosts to invalidate lines before ownership transfer
                for (uint8_t other = 0; other < 4; ++other) {
                    if (other != h_idx) {
                        monitor.onSnoopDispatched(line_addr, other);
                        auto snoop_res = hosts[other]->handleBackInvalidation(line_addr, pintle::BackInvalidateOp::BI_SNP_INV);
                        monitor.onSnoopResponse(line_addr, other, snoop_res.first);
                    }
                }

                monitor.onRequestDispatched(req, cycle);

                // Commit write to memory pool backing store
                memory_pool[line_addr] = wr_payload;

                pintle::CxlMemResponse rsp;
                rsp.host_id = req.host_id;
                rsp.port_id = req.port_id;
                rsp.tag = req.tag;
                rsp.status = pintle::CxlRspStatus::RSP_SUCCESS;
                rsp.has_data = false;

                hosts[h_idx]->handleResponse(rsp);
                monitor.onResponseReceived(rsp, cycle + 16);
                transactions_issued++;
            }
        }
    }

    std::cout << "[Runner] Completed execution of " << transactions_issued
              << " coherent memory transactions.\n";

    monitor.printReport();

    // Verify invariants
    assert(monitor.getCoherenceViolations() == 0 && "Coherence invariant violated!");
    assert(monitor.getCrcErrors() == 0 && "CRC errors detected!");
    assert(transactions_issued > 0 && "Zero transactions executed!");

    std::cout << "[Runner] ALL CO-SIMULATION CHECKS PASSED WITH ZERO ERRORS.\n";
    return 0;
}
