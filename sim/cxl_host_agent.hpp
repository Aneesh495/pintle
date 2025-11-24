/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: sim/cxl_host_agent.hpp
 * Description: Simulated CXL 3.1 Host agent maintaining local cache hierarchy,
 *              generating coherent memory traffic, and servicing Back-Invalidations.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

#ifndef PINTLE_CXL_HOST_AGENT_HPP
#define PINTLE_CXL_HOST_AGENT_HPP

#include "cxl_packet.hpp"
#include <unordered_map>
#include <deque>
#include <memory>
#include <iostream>

namespace pintle {

enum class HostCacheState {
    INVALID,
    SHARED,
    MODIFIED
};

struct HostCacheLine {
    uint64_t       addr;
    HostCacheState state;
    std::array<uint8_t, CACHELINE_BYTES> data;
};

class CxlHostAgent {
public:
    explicit CxlHostAgent(uint8_t host_id, uint8_t port_id);

    // Host traffic generation
    CxlMemRequest issueRead(uint64_t addr);
    CxlMemRequest issueWrite(uint64_t addr, const std::array<uint8_t, CACHELINE_BYTES>& data);

    // Response and snoop handlers
    void handleResponse(const CxlMemResponse& rsp);
    std::pair<BackInvalidateRspStatus, std::array<uint8_t, CACHELINE_BYTES>>
    handleBackInvalidation(uint64_t addr, BackInvalidateOp op);

    // Query state
    uint8_t getHostId() const { return host_id_; }
    HostCacheState getLineState(uint64_t addr) const;
    bool hasLine(uint64_t addr) const;
    const std::array<uint8_t, CACHELINE_BYTES>& getCachedData(uint64_t addr) const;

    size_t getCompletedReads() const { return completed_reads_; }
    size_t getCompletedWrites() const { return completed_writes_; }
    size_t getSnoopsHandled() const { return snoops_handled_; }

private:
    uint8_t  host_id_;
    uint8_t  port_id_;
    uint16_t next_tag_;

    std::unordered_map<uint64_t, HostCacheLine> local_cache_;
    std::unordered_map<uint16_t, uint64_t> in_flight_reads_;
    std::unordered_map<uint16_t, uint64_t> in_flight_writes_;

    size_t completed_reads_;
    size_t completed_writes_;
    size_t snoops_handled_;
};

} // namespace pintle

#endif // PINTLE_CXL_HOST_AGENT_HPP
