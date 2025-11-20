/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: sim/cxl_packet.hpp
 * Description: C++ CXL 3.1 packet definitions, 256-byte standard flit encoders,
 *              Castagnoli CRC-32C calculation, and protocol serialization.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

#ifndef PINTLE_CXL_PACKET_HPP
#define PINTLE_CXL_PACKET_HPP

#include <cstdint>
#include <vector>
#include <string>
#include <array>
#include <sstream>
#include <iomanip>
#include <cstring>

namespace pintle {

// Architectural Constants
constexpr size_t FLIT_SIZE_BYTES = 256;
constexpr size_t CACHELINE_BYTES = 64;
constexpr uint32_t CRC32C_POLYNOMIAL = 0x82F63B78; // Castagnoli reversed bit-order

// Sub-protocol Opcode Definitions
enum class CxlMemOp : uint8_t {
    MEM_OP_READ        = 0,
    MEM_OP_READ_DATA   = 1,
    MEM_OP_WRITE       = 2,
    MEM_OP_WRITE_DATA  = 3,
    MEM_OP_INV         = 4,
    MEM_OP_CLEAN       = 5,
    MEM_OP_FLUSH       = 6
};

enum class CxlRspStatus : uint8_t {
    RSP_SUCCESS        = 0,
    RSP_DATA_READY     = 1,
    RSP_CONFLICT       = 2,
    RSP_ERROR_ECC      = 3,
    RSP_ERROR_TIMEOUT  = 4
};

enum class BackInvalidateOp : uint8_t {
    BI_SNP_INV  = 0,
    BI_SNP_CUR  = 1,
    BI_SNP_DATA = 2
};

enum class BackInvalidateRspStatus : uint8_t {
    BI_RSP_CLEAN = 0,
    BI_RSP_DIRTY = 1,
    BI_RSP_MISS  = 2
};

// CXL.mem M2S (Master to Subordinate) Request Structure
struct CxlMemRequest {
    uint8_t  host_id;
    uint8_t  port_id;
    uint16_t tag;
    CxlMemOp opcode;
    uint64_t addr;
    uint64_t byte_en;
    bool     is_prefetch;
    std::array<uint8_t, CACHELINE_BYTES> data;

    CxlMemRequest()
        : host_id(0), port_id(0), tag(0), opcode(CxlMemOp::MEM_OP_READ),
          addr(0), byte_en(0xFFFFFFFFFFFFFFFFULL), is_prefetch(false) {
        data.fill(0);
    }
};

// CXL.mem S2M (Subordinate to Master) Response Structure
struct CxlMemResponse {
    uint8_t      host_id;
    uint8_t      port_id;
    uint16_t     tag;
    CxlRspStatus status;
    bool         has_data;
    std::array<uint8_t, CACHELINE_BYTES> data;

    CxlMemResponse()
        : host_id(0), port_id(0), tag(0), status(CxlRspStatus::RSP_SUCCESS), has_data(false) {
        data.fill(0);
    }
};

// 256-Byte Standard CXL Flit Representation
struct CxlStandardFlit {
    uint8_t flit_type;
    uint8_t seq_num;
    uint8_t ack_num;
    uint8_t credit_tokens;
    std::array<uint8_t, 256 - 8> payload; // 248 bytes payload + CRC
    uint32_t crc;

    CxlStandardFlit()
        : flit_type(0xC3), seq_num(0), ack_num(0), credit_tokens(0), crc(0) {
        payload.fill(0);
    }
};

// Castagnoli CRC-32C calculation (RFC 3720 / CXL standard)
inline uint32_t compute_crc32c(const uint8_t* buffer, size_t length) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < length; ++i) {
        crc ^= buffer[i];
        for (int b = 0; b < 8; ++b) {
            if (crc & 1) {
                crc = (crc >> 1) ^ CRC32C_POLYNOMIAL;
            } else {
                crc >>= 1;
            }
        }
    }
    return ~crc;
}

// Format CxlMemRequest for logging
inline std::string format_request(const CxlMemRequest& req) {
    std::ostringstream oss;
    oss << "[M2S Req] host=" << static_cast<int>(req.host_id)
        << " port=" << static_cast<int>(req.port_id)
        << " tag=0x" << std::hex << std::setw(3) << std::setfill('0') << req.tag
        << " op=" << static_cast<int>(req.opcode)
        << " addr=0x" << std::hex << std::setw(16) << std::setfill('0') << req.addr;
    return oss.str();
}

// Format CxlMemResponse for logging
inline std::string format_response(const CxlMemResponse& rsp) {
    std::ostringstream oss;
    oss << "[S2M Rsp] host=" << static_cast<int>(rsp.host_id)
        << " port=" << static_cast<int>(rsp.port_id)
        << " tag=0x" << std::hex << std::setw(3) << std::setfill('0') << rsp.tag
        << " status=" << static_cast<int>(rsp.status)
        << " has_data=" << (rsp.has_data ? "true" : "false");
    return oss.str();
}

} // namespace pintle

#endif // PINTLE_CXL_PACKET_HPP
