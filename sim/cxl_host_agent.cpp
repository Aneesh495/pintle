/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: sim/cxl_host_agent.cpp
 * Description: Implementation of CXL 3.1 Host Agent with local cache state machine.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

#include "cxl_host_agent.hpp"

namespace pintle {

CxlHostAgent::CxlHostAgent(uint8_t host_id, uint8_t port_id)
    : host_id_(host_id),
      port_id_(port_id),
      next_tag_(1),
      completed_reads_(0),
      completed_writes_(0),
      snoops_handled_(0) {}

CxlMemRequest CxlHostAgent::issueRead(uint64_t addr) {
    uint64_t aligned_addr = addr & ~0x3FULL;

    CxlMemRequest req;
    req.host_id = host_id_;
    req.port_id = port_id_;
    req.tag = next_tag_++;
    req.opcode = CxlMemOp::MEM_OP_READ;
    req.addr = aligned_addr;
    req.byte_en = 0xFFFFFFFFFFFFFFFFULL;
    req.is_prefetch = false;

    in_flight_reads_[req.tag] = aligned_addr;
    return req;
}

CxlMemRequest CxlHostAgent::issueWrite(uint64_t addr, const std::array<uint8_t, CACHELINE_BYTES>& data) {
    uint64_t aligned_addr = addr & ~0x3FULL;

    CxlMemRequest req;
    req.host_id = host_id_;
    req.port_id = port_id_;
    req.tag = next_tag_++;
    req.opcode = CxlMemOp::MEM_OP_WRITE_DATA;
    req.addr = aligned_addr;
    req.byte_en = 0xFFFFFFFFFFFFFFFFULL;
    req.is_prefetch = false;
    req.data = data;

    in_flight_writes_[req.tag] = aligned_addr;
    return req;
}

void CxlHostAgent::handleResponse(const CxlMemResponse& rsp) {
    auto rd_it = in_flight_reads_.find(rsp.tag);
    if (rd_it != in_flight_reads_.end()) {
        uint64_t addr = rd_it->second;
        in_flight_reads_.erase(rd_it);

        HostCacheLine line;
        line.addr = addr;
        line.state = HostCacheState::SHARED;
        line.data = rsp.data;
        local_cache_[addr] = line;
        completed_reads_++;
        return;
    }

    auto wr_it = in_flight_writes_.find(rsp.tag);
    if (wr_it != in_flight_writes_.end()) {
        uint64_t addr = wr_it->second;
        in_flight_writes_.erase(wr_it);

        auto it = local_cache_.find(addr);
        if (it != local_cache_.end()) {
            it->second.state = HostCacheState::MODIFIED;
        }
        completed_writes_++;
        return;
    }
}

std::pair<BackInvalidateRspStatus, std::array<uint8_t, CACHELINE_BYTES>>
CxlHostAgent::handleBackInvalidation(uint64_t addr, BackInvalidateOp op) {
    snoops_handled_++;
    uint64_t aligned_addr = addr & ~0x3FULL;

    auto it = local_cache_.find(aligned_addr);
    if (it == local_cache_.end() || it->second.state == HostCacheState::INVALID) {
        std::array<uint8_t, CACHELINE_BYTES> empty_data{};
        return {BackInvalidateRspStatus::BI_RSP_MISS, empty_data};
    }

    if (it->second.state == HostCacheState::MODIFIED) {
        auto dirty_data = it->second.data;
        if (op == BackInvalidateOp::BI_SNP_INV || op == BackInvalidateOp::BI_SNP_DATA) {
            it->second.state = HostCacheState::INVALID;
        } else {
            it->second.state = HostCacheState::SHARED;
        }
        return {BackInvalidateRspStatus::BI_RSP_DIRTY, dirty_data};
    } else {
        if (op == BackInvalidateOp::BI_SNP_INV || op == BackInvalidateOp::BI_SNP_DATA) {
            it->second.state = HostCacheState::INVALID;
        }
        std::array<uint8_t, CACHELINE_BYTES> empty_data{};
        return {BackInvalidateRspStatus::BI_RSP_CLEAN, empty_data};
    }
}

HostCacheState CxlHostAgent::getLineState(uint64_t addr) const {
    uint64_t aligned_addr = addr & ~0x3FULL;
    auto it = local_cache_.find(aligned_addr);
    if (it == local_cache_.end()) {
        return HostCacheState::INVALID;
    }
    return it->second.state;
}

bool CxlHostAgent::hasLine(uint64_t addr) const {
    return getLineState(addr) != HostCacheState::INVALID;
}

const std::array<uint8_t, CACHELINE_BYTES>& CxlHostAgent::getCachedData(uint64_t addr) const {
    uint64_t aligned_addr = addr & ~0x3FULL;
    static const std::array<uint8_t, CACHELINE_BYTES> zero_data{};
    auto it = local_cache_.find(aligned_addr);
    if (it == local_cache_.end()) {
        return zero_data;
    }
    return it->second.data;
}

} // namespace pintle
