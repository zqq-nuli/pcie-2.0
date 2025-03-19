//
// PCILeech FPGA.
//
// PCIe configuration module - CFG handling for Artix-7.
//
// (c) Ulf Frisk, 2018-2024
// Author: Ulf Frisk, pcileech@frizk.net
//

`timescale 1ns / 1ps
`include "pcileech_header.svh"

module pcileech_pcie_cfg_a7(
    input                   rst,
    input                   clk_sys,
    input                   clk_pcie,
    IfPCIeFifoCfg.mp_pcie   dfifo,
    IfPCIeSignals.mpm       ctx,
    IfAXIS128.source        tlps_static,
    input                   i_valid,
    input [31:0]            i_addr,
    input [31:0]            i_data,
    input                   int_enable,
    output [15:0]           pcie_id,
    output wire [31:0]      base_address_register
    );

    // ----------------------------------------------------
    // TickCount64
    // ----------------------------------------------------
    
    time tickcount64 = 0;
    always @ ( posedge clk_pcie )
        tickcount64 <= tickcount64 + 1;
    // ----------------------------------------------------
    // RTL8111电源管理状态定义和寄存器
    // ----------------------------------------------------
    // 电源状态定义
    localparam PM_STATE_D0 = 2'b00;    // 正常工作状态
    localparam PM_STATE_D1 = 2'b01;    // 低功耗状态1
    localparam PM_STATE_D2 = 2'b10;    // 低功耗状态2
    localparam PM_STATE_D3 = 2'b11;    // 关闭状态 

    // RTL8111电源管理寄存器
    reg [1:0] rtl8111_pm_state;         // 当前电源状态
    reg       rtl8111_pm_pme_status;    // 电源管理事件状态
    reg       rtl8111_pm_pme_enable;    // 电源管理事件使能
    reg [7:0] rtl8111_pm_wakeup_config; // 唤醒配置寄存器
    // 添加网络流量模式定义
    // 定义不同类型的网络流量模式常量
    localparam TRAFFIC_IDLE = 0;       // 空闲模式
    localparam TRAFFIC_BROWSING = 1;   // 浏览模式
    localparam TRAFFIC_GAMING = 2;     // 游戏模式
    localparam TRAFFIC_DOWNLOAD = 3;   // 下载模式
    localparam TRAFFIC_UPLOAD = 4;     // 上传模式

    reg [2:0] network_event_type;      // 网络事件类型：0=接收数据包, 1=发送完成, 2=链路状态变化
    reg [31:0] packet_size_counter;    // 数据包大小计数器，用于记录当前模拟的数据包大小

    // 当前流量模式和相关计数器
    reg [2:0] current_traffic_mode;
    reg [31:0] traffic_mode_duration;
    reg [31:0] packet_interval;
    reg [15:0] packet_count_in_burst;
    reg [15:0] current_packet_count;
    reg [31:0] last_tx_timestamp;
    reg [31:0] last_rx_timestamp;
        
    // 添加更完整的RTL8111寄存器
    reg [31:0] rtl8111_registers[0:127];  // 128个32位寄存器空间
    reg [31:0] rtl8111_rx_desc_addr;      // 接收描述符地址
    reg [31:0] rtl8111_tx_desc_addr;      // 发送描述符地址
    reg [15:0] rtl8111_int_status;        // 中断状态寄存器 (ISR)
    reg [15:0] rtl8111_int_mask;          // 中断掩码寄存器 (IMR)
    reg [7:0]  rtl8111_cmd;               // 命令寄存器
    reg [7:0]  rtl8111_tx_status;         // 发送状态
    reg [7:0]  rtl8111_rx_status;         // 接收状态
    reg [7:0]  rtl8111_link_status;       // 链路状态
    reg [15:0] rtl8111_phy_status;        // PHY状态寄存器
    // 添加中断请求信号
    reg int_req_tx_ok;         // 0x0004 - TX OK
    reg int_req_rx_ok;         // 0x0001 - RX OK
    reg int_req_link_change;   // 0x0020 - 链路状态变化
    reg int_req_wakeup;        // 0x2000 - 唤醒事件
    reg int_req_clear;         // 写入清除请求
    reg [15:0] int_clear_mask; // 要清除的中断位掩码

    // 2. 增加中间控制信号(用于不同always块之间传递控制意图)
    reg int_req_tx_ok_set;         // 设置TX OK中断请求
    reg int_req_rx_ok_set;         // 设置RX OK中断请求
    reg int_req_link_change_set;   // 设置链路状态变化中断请求
    reg int_req_wakeup_set;        // 设置唤醒事件中断请求
    reg int_req_clear_set;         // 写入清除请求设置
    reg [15:0] int_clear_mask_val; // 要清除的中断位掩码值

    // 3. 增加PHY和RX状态控制信号
    reg update_phy_status;         // 更新PHY状态标志
    reg [15:0] phy_status_new;     // 新的PHY状态值
    reg update_rx_status;          // 更新接收状态标志
    reg [7:0] rx_status_new;       // 新的接收状态值
    
    // ----------------------------------------------------------------------------
    // Convert received CFG data from FT601 to PCIe clock domain
    // FIFO depth: 512 / 64-bits
    // ----------------------------------------------------------------------------
    reg             in_rden;
    wire [63:0]     in_dout;
    wire            in_empty;
    wire            in_valid;
    
    reg [63:0]      in_data64;
    wire [31:0]     in_data32   = in_data64[63:32];
    wire [15:0]     in_data16   = in_data64[31:16];
    wire [3:0]      in_type     = in_data64[15:12];
	
    fifo_64_64 i_fifo_pcie_cfg_tx(
        .rst            ( rst                   ),
        .wr_clk         ( clk_sys               ),
        .rd_clk         ( clk_pcie              ),
        .din            ( dfifo.tx_data         ),
        .wr_en          ( dfifo.tx_valid        ),
        .rd_en          ( in_rden               ),
        .dout           ( in_dout               ),
        .full           (                       ),
        .empty          ( in_empty              ),
        .valid          ( in_valid              )
    );
    
    // ------------------------------------------------------------------------
    // Convert received CFG from PCIe core and transmit onwards to FT601
    // FIFO depth: 512 / 64-bits.
    // ------------------------------------------------------------------------
    reg             out_wren;
    reg [31:0]      out_data;
    wire            pcie_cfg_rx_almost_full;
    
    fifo_32_32_clk2 i_fifo_pcie_cfg_rx(
        .rst            ( rst                   ),
        .wr_clk         ( clk_pcie              ),
        .rd_clk         ( clk_sys               ),
        .din            ( out_data              ),
        .wr_en          ( out_wren              ),
        .rd_en          ( dfifo.rx_rd_en        ),
        .dout           ( dfifo.rx_data         ),
        .full           (                       ),
        .almost_full    ( pcie_cfg_rx_almost_full ),
        .empty          (                       ),
        .valid          ( dfifo.rx_valid        )
    );
    
    // ------------------------------------------------------------------------
    // REGISTER FILE: COMMON
    // ------------------------------------------------------------------------
    
    wire    [383:0]     ro;
    reg     [703:0]     rw;
    
    // special non-user accessible registers 
    reg                 rwi_cfg_mgmt_rd_en;
    reg                 rwi_cfg_mgmt_wr_en;
    reg                 rwi_cfgrd_valid;
    reg     [9:0]       rwi_cfgrd_addr;
    reg     [3:0]       rwi_cfgrd_byte_en;
    reg     [31:0]      rwi_cfgrd_data;
    reg                 rwi_tlp_static_valid;
    reg                 rwi_tlp_static_2nd;
    reg                 rwi_tlp_static_has_data;
    reg     [31:0]      rwi_count_cfgspace_status_cl;
    bit     [31:0]      base_address_register_reg;
    integer i_write, i_tlpstatic;
   
    // ------------------------------------------------------------------------
    // REGISTER FILE: READ-ONLY LAYOUT/SPECIFICATION
    // ------------------------------------------------------------------------
     
    // MAGIC
    assign base_address_register = base_address_register_reg;
    assign ro[15:0]     = 16'h2301;                     // +000: MAGIC
    // SPECIAL
    assign ro[16]       = ctx.cfg_mgmt_rd_en;           // +002: SPECIAL
    assign ro[17]       = ctx.cfg_mgmt_wr_en;           //
    assign ro[31:18]    = 0;                            //
    // SIZEOF / BYTECOUNT [little-endian]
    assign ro[63:32]    = $bits(ro) >> 3;               // +004: BYTECOUNT
    // PCIe CFG STATUS
    assign ro[71:64]    = ctx.cfg_bus_number;           // +008:
    assign ro[76:72]    = ctx.cfg_device_number;        //
    assign ro[79:77]    = ctx.cfg_function_number;      //
    // PCIe PL PHY
    assign ro[85:80]    = ctx.pl_ltssm_state;           // +00A
    assign ro[87:86]    = ctx.pl_rx_pm_state;           //
    assign ro[90:88]    = ctx.pl_tx_pm_state;           // +00B
    assign ro[93:91]    = ctx.pl_initial_link_width;    //
    assign ro[95:94]    = ctx.pl_lane_reversal_mode;    //
    assign ro[97:96]    = ctx.pl_sel_lnk_width;         // +00C
    assign ro[98]       = ctx.pl_phy_lnk_up;            //
    assign ro[99]       = ctx.pl_link_gen2_cap;         //
    assign ro[100]      = ctx.pl_link_partner_gen2_supported; //
    assign ro[101]      = ctx.pl_link_upcfg_cap;        //
    assign ro[102]      = ctx.pl_sel_lnk_rate;          //
    assign ro[103]      = ctx.pl_directed_change_done;  // +00D:
    assign ro[104]      = ctx.pl_received_hot_rst;      //
    assign ro[126:105]  = 0;                            //       SLACK
    assign ro[127]      = ctx.cfg_mgmt_rd_wr_done;      //
    // PCIe CFG MGMT
    assign ro[159:128]  = ctx.cfg_mgmt_do;              // +010:
    // PCIe CFG STATUS
    assign ro[175:160]  = ctx.cfg_command;              // +014:
    assign ro[176]      = ctx.cfg_aer_rooterr_corr_err_received;            // +016:
    assign ro[177]      = ctx.cfg_aer_rooterr_corr_err_reporting_en;        //
    assign ro[178]      = ctx.cfg_aer_rooterr_fatal_err_received;           //
    assign ro[179]      = ctx.cfg_aer_rooterr_fatal_err_reporting_en;       //
    assign ro[180]      = ctx.cfg_aer_rooterr_non_fatal_err_received;       //
    assign ro[181]      = ctx.cfg_aer_rooterr_non_fatal_err_reporting_en;   //
    assign ro[182]      = ctx.cfg_bridge_serr_en;                           //
    assign ro[183]      = ctx.cfg_received_func_lvl_rst;                    //
    assign ro[186:184]  = ctx.cfg_pcie_link_state;      // +017:
    assign ro[187]      = ctx.cfg_pmcsr_pme_en;         //
    assign ro[189:188]  = ctx.cfg_pmcsr_powerstate;     //
    assign ro[190]      = ctx.cfg_pmcsr_pme_status;     //
    assign ro[191]      = 0;                            //       SLACK
    assign ro[207:192]  = ctx.cfg_dcommand;             // +018:
    assign ro[223:208]  = ctx.cfg_dcommand2;            // +01A:
    assign ro[239:224]  = ctx.cfg_dstatus;              // +01C:
    assign ro[255:240]  = ctx.cfg_lcommand;             // +01E:
    assign ro[271:256]  = ctx.cfg_lstatus;              // +020:
    assign ro[287:272]  = ctx.cfg_status;               // +022:
    assign ro[293:288]  = ctx.tx_buf_av;                // +024:
    assign ro[294]      = ctx.tx_cfg_req;               //
    assign ro[295]      = ctx.tx_err_drop;              //
    assign ro[302:296]  = ctx.cfg_vc_tcvc_map;          // +025:
    assign ro[303]      = 0;                            //       SLACK
    assign ro[304]      = ctx.cfg_root_control_pme_int_en;              // +026:
    assign ro[305]      = ctx.cfg_root_control_syserr_corr_err_en;      //
    assign ro[306]      = ctx.cfg_root_control_syserr_fatal_err_en;     //
    assign ro[307]      = ctx.cfg_root_control_syserr_non_fatal_err_en; //
    assign ro[308]      = ctx.cfg_slot_control_electromech_il_ctl_pulse;//
    assign ro[309]      = ctx.cfg_to_turnoff;                           //
    assign ro[319:310]  = 0;                                            //       SLACK
    // PCIe INTERRUPT
    assign ro[327:320]  = ctx.cfg_interrupt_do;         // +028:
    assign ro[330:328]  = ctx.cfg_interrupt_mmenable;   // +029:
    assign ro[331]      = ctx.cfg_interrupt_msienable;  //
    assign ro[332]      = ctx.cfg_interrupt_msixenable; //
    assign ro[333]      = ctx.cfg_interrupt_msixfm;     //
    assign ro[334]      = ctx.cfg_interrupt_rdy;        //
    assign ro[335]      = 0;                            //       SLACK
    // CFG SPACE READ RESULT
    assign ro[345:336]  = rwi_cfgrd_addr;               // +02A:
    assign ro[346]      = 0;                            //       SLACK
    assign ro[347]      = rwi_cfgrd_valid;              //
    assign ro[351:348]  = rwi_cfgrd_byte_en;            //
    assign ro[383:352]  = rwi_cfgrd_data;               // +02C:
    // 0030 - 
    
    
    // ------------------------------------------------------------------------
    // INITIALIZATION/RESET BLOCK _AND_
    // REGISTER FILE: READ-WRITE LAYOUT/SPECIFICATION
    // ------------------------------------------------------------------------
    
    localparam integer  RWPOS_CFG_RD_EN                 = 16;
    localparam integer  RWPOS_CFG_WR_EN                 = 17;
    localparam integer  RWPOS_CFG_WAIT_COMPLETE         = 18;
    localparam integer  RWPOS_CFG_STATIC_TLP_TX_EN      = 19;
    localparam integer  RWPOS_CFG_CFGSPACE_STATUS_CL_EN = 20;
    localparam integer  RWPOS_CFG_CFGSPACE_COMMAND_EN   = 21;
    
    task pcileech_pcie_cfg_a7_initialvalues;        // task is non automatic
        begin
            out_wren <= 1'b0;
            
            rwi_cfg_mgmt_rd_en <= 1'b0;
            rwi_cfg_mgmt_wr_en <= 1'b0;
            base_address_register_reg <= 32'h00000000;
            // 初始化RTL8111寄存器
            for (i_write = 0; i_write < 128; i_write = i_write + 1) begin
                rtl8111_registers[i_write] <= 32'h00000000;
            end
            
            // 设置特定寄存器初始值
            rtl8111_registers[0] <= 32'h10EC8168; // 设备ID和厂商ID寄存器 (RTL8111)
            rtl8111_registers[4] <= 32'h00100007; // 命令和状态寄存器 (启用总线主控)
            rtl8111_registers[8] <= 32'h02000000; // 类代码寄存器 (网络控制器)
            
            // 初始化关键寄存器
            rtl8111_rx_desc_addr <= 32'h00000000;
            rtl8111_tx_desc_addr <= 32'h00000000;
            rtl8111_int_status <= 16'h0000;       // 清空中断状态
            rtl8111_int_mask <= 16'hffff;         // 默认允许所有中断
            rtl8111_cmd <= 8'h0C;                 // 默认Tx/Rx使能
            rtl8111_tx_status <= 8'h80;           // Tx空闲
            rtl8111_rx_status <= 8'h01;           // Rx就绪
            rtl8111_link_status <= 8'h04;         // 链路已连接，1Gbps
            rtl8111_phy_status <= 16'h7809;       // PHY状态：链路已建立
            // 初始化RTL8111电源管理寄存器
            rtl8111_pm_state <= PM_STATE_D0;         // 初始为正常工作状态
            rtl8111_pm_pme_status <= 1'b0;           // 初始无电源管理事件
            rtl8111_pm_pme_enable <= 1'b0;           // 初始禁用电源管理事件
            rtl8111_pm_wakeup_config <= 8'h00;       // 初始禁用所有唤醒事件
            // MAGIC
            rw[15:0]    <= 16'h6745;                // +000:
            // SPECIAL START TASK BLOCK (write 1 to start action)
            rw[16]      <= 0;                       // +002: CFG RD EN
            rw[17]      <= 0;                       //       CFG WR EN
            rw[18]      <= 0;                       //       WAIT FOR PCIe CFG SPACE RD/WR COMPLETION BEFORE ACCEPT NEW FIFO READ/WRITES
            rw[19]      <= 0;                       //       TLP_STATIC TX ENABLE
            rw[20]      <= 1;                       //       CFGSPACE_STATUS_REGISTER_AUTO_CLEAR [master abort flag]
            rw[21]      <= 0;                       //       CFGSPACE_COMMAND_REGISTER_AUTO_SET [bus master and other flags (set in rw[143:128] <= 16'h....;)]
            rw[31:22]   <= 0;                       //       RESERVED FUTURE
            // SIZEOF / BYTECOUNT [little-endian]
            rw[63:32]   <= $bits(rw) >> 3;          // +004: bytecount [little endian]
            // DSN
            rw[127:64]  <= 64'h2C000000684CE000;    // +008: cfg_dsn
            // PCIe CFG MGMT
            rw[159:128] <= 0;                       // +010: cfg_mgmt_di
            rw[169:160] <= 0;                       // +014: cfg_mgmt_dwaddr
            rw[170]     <= 0;                       //       cfg_mgmt_wr_readonly
            rw[171]     <= 0;                       //       cfg_mgmt_wr_rw1c_as_rw
            rw[175:172] <= 4'hf;                    //       cfg_mgmt_byte_en
            // PCIe PL PHY
            rw[176]     <= 0;                       // +016: pl_directed_link_auton
            rw[178:177] <= 0;                       //       pl_directed_link_change
            rw[179]     <= 1;                       //       pl_directed_link_speed 
            rw[181:180] <= 0;                       //       pl_directed_link_width            
            rw[182]     <= 1;                       //       pl_upstream_prefer_deemph
            rw[183]     <= 0;                       //       pl_transmit_hot_rst
            rw[184]     <= 0;                       // +017: pl_downstream_deemph_source
            rw[191:185] <= 0;                       //       SLACK  
            // PCIe INTERRUPT
            rw[199:192] <= 0;                       // +018: cfg_interrupt_di
            rw[204:200] <= 0;                       // +019: cfg_pciecap_interrupt_msgnum
            rw[205]     <= 0;                       //       cfg_interrupt_assert
            rw[206]     <= 0;                       //       cfg_interrupt
            rw[207]     <= 0;                       //       cfg_interrupt_stat
            // PCIe CTRL
            rw[209:208] <= 0;                       // +01A: cfg_pm_force_state
            rw[210]     <= 0;                       //       cfg_pm_force_state_en
            rw[211]     <= 0;                       //       cfg_pm_halt_aspm_l0s
            rw[212]     <= 0;                       //       cfg_pm_halt_aspm_l1
            rw[213]     <= 0;                       //       cfg_pm_send_pme_to
            rw[214]     <= 0;                       //       cfg_pm_wake
            rw[215]     <= 0;                       //       cfg_trn_pending
            rw[216]     <= 0;                       // +01B: cfg_turnoff_ok
            rw[217]     <= 1;                       //       rx_np_ok
            rw[218]     <= 1;                       //       rx_np_req
            rw[219]     <= 1;                       //       tx_cfg_gnt
            rw[223:220] <= 0;                       //       SLACK 
            // PCIe STATIC TLP TRANSMIT
            rw[224+:8]  <= 0;                       // +01C: TLP_STATIC TLP DWORD VALID [each-2bit: [0] = last, [1] = valid] [TLP DWORD 0-3]
            rw[232+:8]  <= 0;                       // +01D: TLP_STATIC TLP DWORD VALID [each-2bit: [0] = last, [1] = valid] [TLP DWORD 4-7]
            rw[240+:16] <= 0;                       // +01E: TLP_STATIC TLP TX SLEEP (ticks) [little-endian]
            rw[256+:384] <= 0;                      // +020: TLP_STATIC TLP [8*32-bit hdr+data]
            rw[640+:32] <= 0;                       // +050: TLP_STATIC TLP RETRANSMIT COUNT
            // PCIe STATUS register clear timer
            rw[672+:32] <= 62500;                   // +054: CFGSPACE_STATUS_CLEAR TIMER (ticks) [little-endian] [default = 1ms - 62.5k @ 62.5MHz]
            
        end
    endtask
    reg[7:0] cfg_int_di;
    reg[4:0] cfg_msg_num;
    reg cfg_int_assert;
    reg cfg_int_valid;
    wire cfg_int_ready = ctx.cfg_interrupt_rdy;
    reg cfg_int_stat; 
    
    assign ctx.cfg_mgmt_rd_en               = rwi_cfg_mgmt_rd_en & ~ctx.cfg_mgmt_rd_wr_done;
    assign ctx.cfg_mgmt_wr_en               = rwi_cfg_mgmt_wr_en & ~ctx.cfg_mgmt_rd_wr_done;
    
    assign ctx.cfg_dsn                      = rw[127:64];
    assign ctx.cfg_mgmt_di                  = rw[159:128];
    assign ctx.cfg_mgmt_dwaddr              = rw[169:160];
    assign ctx.cfg_mgmt_wr_readonly         = rw[170];
    assign ctx.cfg_mgmt_wr_rw1c_as_rw       = rw[171];
    assign ctx.cfg_mgmt_byte_en             = rw[175:172];
    
    assign ctx.pl_directed_link_auton       = rw[176];
    assign ctx.pl_directed_link_change      = rw[178:177];
    assign ctx.pl_directed_link_speed       = rw[179];
    assign ctx.pl_directed_link_width       = rw[181:180];
    assign ctx.pl_upstream_prefer_deemph    = rw[182];
    assign ctx.pl_transmit_hot_rst          = rw[183];
    assign ctx.pl_downstream_deemph_source  = rw[184];
    
    // assign ctx.cfg_interrupt_di             = rw[199:192];
    // assign ctx.cfg_pciecap_interrupt_msgnum = rw[204:200];
    // assign ctx.cfg_interrupt_assert         = rw[205];
    // assign ctx.cfg_interrupt                = rw[206];
    // assign ctx.cfg_interrupt_stat           = rw[207];

    	
    assign ctx.cfg_interrupt_di             = cfg_int_di;
    assign ctx.cfg_pciecap_interrupt_msgnum = cfg_msg_num;
    assign ctx.cfg_interrupt_assert         = cfg_int_assert;
    assign ctx.cfg_interrupt                = cfg_int_valid;
    assign ctx.cfg_interrupt_stat           = cfg_int_stat;

    assign ctx.cfg_pm_force_state           = rw[209:208];
    assign ctx.cfg_pm_force_state_en        = rw[210];
    assign ctx.cfg_pm_halt_aspm_l0s         = rw[211];
    assign ctx.cfg_pm_halt_aspm_l1          = rw[212];
    assign ctx.cfg_pm_send_pme_to           = rw[213];
    assign ctx.cfg_pm_wake                  = rw[214];
    assign ctx.cfg_trn_pending              = rw[215];
    assign ctx.cfg_turnoff_ok               = rw[216];
    assign ctx.rx_np_ok                     = rw[217];
    assign ctx.rx_np_req                    = rw[218];
    assign ctx.tx_cfg_gnt                   = rw[219];
    
    // assign tlps_static.tdata[127:0]         = rwi_tlp_static_2nd ? {
    //     rw[(256+32*7+00)+:8], rw[(256+32*7+08)+:8], rw[(256+32*7+16)+:8], rw[(256+32*7+24)+:8],   // STATIC TLP DWORD7
    //     rw[(256+32*6+00)+:8], rw[(256+32*6+08)+:8], rw[(256+32*6+16)+:8], rw[(256+32*6+24)+:8],   // STATIC TLP DWORD6
    //     rw[(256+32*5+00)+:8], rw[(256+32*5+08)+:8], rw[(256+32*5+16)+:8], rw[(256+32*5+24)+:8],   // STATIC TLP DWORD5
    //     rw[(256+32*4+00)+:8], rw[(256+32*4+08)+:8], rw[(256+32*4+16)+:8], rw[(256+32*4+24)+:8]    // STATIC TLP DWORD4
    // } : {
    //     rw[(256+32*3+00)+:8], rw[(256+32*3+08)+:8], rw[(256+32*3+16)+:8], rw[(256+32*3+24)+:8],   // STATIC TLP DWORD3
    //     rw[(256+32*2+00)+:8], rw[(256+32*2+08)+:8], rw[(256+32*2+16)+:8], rw[(256+32*2+24)+:8],   // STATIC TLP DWORD2
    //     rw[(256+32*1+00)+:8], rw[(256+32*1+08)+:8], rw[(256+32*1+16)+:8], rw[(256+32*1+24)+:8],   // STATIC TLP DWORD1
    //     rw[(256+32*0+00)+:8], rw[(256+32*0+08)+:8], rw[(256+32*0+16)+:8], rw[(256+32*0+24)+:8]    // STATIC TLP DWORD0
    // };
    // assign tlps_static.tkeepdw              = rwi_tlp_static_2nd ? { rw[224+2*7], rw[224+2*6], rw[224+2*5], rw[224+2*4] } : { rw[224+2*3], rw[224+2*2], rw[224+2*1], rw[224+2*0] };
    // assign tlps_static.tlast                = rwi_tlp_static_2nd || rw[224+2*3+1] || rw[224+2*2+1] || rw[224+2*1+1] || rw[224+2*0+1];
    // assign tlps_static.tuser[0]             = !rwi_tlp_static_2nd;
    // assign tlps_static.tvalid               = rwi_tlp_static_valid && tlps_static.tkeepdw[0];
    // assign tlps_static.has_data             = rwi_tlp_static_has_data;
        
    bit msix_valid;
    bit msix_has_data;
    bit[127:0] msix_tlp;
    assign tlps_static.tdata[127:0] = msix_tlp;
    assign tlps_static.tkeepdw  = 4'hf;
    assign tlps_static.tlast   = 1'b1;
    assign tlps_static.tuser[0] = 1'b1;
    assign tlps_static.tvalid   = msix_valid;
    assign tlps_static.has_data   = msix_has_data;
    assign pcie_id                          = ro[79:64];
    
    // ------------------------------------------------------------------------
    // STATE MACHINE / LOGIC FOR READ/WRITE AND OTHER HOUSEKEEPING TASKS
    // ------------------------------------------------------------------------
    
    wire [15:0] in_cmd_address_byte = in_dout[31:16];
    wire [17:0] in_cmd_address_bit  = {in_cmd_address_byte[14:0], 3'b000};
    wire [15:0] in_cmd_value        = {in_dout[48+:8], in_dout[56+:8]};
    wire [15:0] in_cmd_mask         = {in_dout[32+:8], in_dout[40+:8]};
    wire        f_rw                = in_cmd_address_byte[15]; 
    wire [15:0] in_cmd_data_in      = (in_cmd_address_bit < (f_rw ? $bits(rw) : $bits(ro))) ? (f_rw ? rw[in_cmd_address_bit+:16] : ro[in_cmd_address_bit+:16]) : 16'h0000;
    wire        in_cmd_read         = in_dout[12] & in_valid;
    wire        in_cmd_write        = in_dout[13] & in_cmd_address_byte[15] & in_valid;
    wire        pcie_cfg_rw_en      = rwi_cfg_mgmt_rd_en | rwi_cfg_mgmt_wr_en | rw[RWPOS_CFG_RD_EN] | rw[RWPOS_CFG_WR_EN];
    // in_rden = request data from incoming fifo. Only do this if there is space
    // in the output fifo and every 2nd clock cycle (in case a resulting write
    // starts an action that will last longer than a single clock there must be
    // time to react and stop reading incoming read/writes until processed).
    assign in_rden = tickcount64[1] & ~pcie_cfg_rx_almost_full & ( ~rw[RWPOS_CFG_WAIT_COMPLETE] | ~pcie_cfg_rw_en);
    wire      [31:0] HDR_MEMWR64 = 32'b01000000_00000000_00000000_00000001;
   // localparam [31:0] MWR64_DW2   = {, 8'b00000000, 8'b00001111};
    wire       [31:0] MWR64_DW2  = {`_bs16(pcie_id), 8'b00000000, 8'b00001111};
    wire       [31:0] MWR64_DW3  = {i_addr[31:2], 2'b0};
    wire       [31:0] MWR64_DW4  = {i_data};
    wire o_int;
    initial pcileech_pcie_cfg_a7_initialvalues();
    
    always @ ( posedge clk_pcie )
        if ( rst )
            pcileech_pcie_cfg_a7_initialvalues();
        else
            begin
                // READ config
                out_wren <= in_cmd_read;
                if ( in_cmd_read )
                    begin
                        out_data[31:16] <= in_cmd_address_byte;
                        out_data[15:0]  <= {in_cmd_data_in[7:0], in_cmd_data_in[15:8]};
                    end

                // WRITE config
                if ( in_cmd_write )
                    for ( i_write = 0; i_write < 16; i_write = i_write + 1 )
                        begin
                            if ( in_cmd_mask[i_write] )
                                rw[in_cmd_address_bit+i_write] <= in_cmd_value[i_write];
                        end

                // STATUS REGISTER CLEAR
                if ( (rw[RWPOS_CFG_CFGSPACE_STATUS_CL_EN] | rw[RWPOS_CFG_CFGSPACE_COMMAND_EN]) & ~in_cmd_read & ~in_cmd_write & ~rw[RWPOS_CFG_RD_EN] & ~rw[RWPOS_CFG_WR_EN] & ~rwi_cfg_mgmt_rd_en & ~rwi_cfg_mgmt_wr_en )
                    if ( rwi_count_cfgspace_status_cl < rw[672+:32] )
                        rwi_count_cfgspace_status_cl <= rwi_count_cfgspace_status_cl + 1;
                    else begin
                        rwi_count_cfgspace_status_cl <= 0;
                        rw[RWPOS_CFG_WR_EN] <= 1'b1;
                        rw[143:128] <= 16'h0407;                            // cfg_mgmt_di: command register [update to set individual command register bits]
                        rw[159:144] <= 16'hff10;                            // cfg_mgmt_di: status register [do not update]
                        rw[169:160] <= 1;                                   // cfg_mgmt_dwaddr
                        rw[170]     <= 0;                                   // cfg_mgmt_wr_readonly
                        rw[171]     <= 0;                                   // cfg_mgmt_wr_rw1c_as_rw
                        rw[172]     <= rw[RWPOS_CFG_CFGSPACE_COMMAND_EN];   // cfg_mgmt_byte_en: command register
                        rw[173]     <= rw[RWPOS_CFG_CFGSPACE_COMMAND_EN];   // cfg_mgmt_byte_en: command register
                        rw[174]     <= 0;                                   // cfg_mgmt_byte_en: status register
                        rw[175]     <= rw[RWPOS_CFG_CFGSPACE_STATUS_CL_EN]; // cfg_mgmt_byte_en: status register
                    end

                if ((base_address_register_reg == 32'h00000000) | (base_address_register_reg == 32'hFFFFFF00)  | (base_address_register_reg == 32'h00000004) )
                    if ( ~in_cmd_read & ~in_cmd_write & ~rw[RWPOS_CFG_RD_EN] & ~rw[RWPOS_CFG_WR_EN] & ~rwi_cfg_mgmt_rd_en & ~rwi_cfg_mgmt_wr_en )
                        begin
                            rw[RWPOS_CFG_RD_EN] <= 1'b1;
                            rw[169:160] <= 6;                                   // cfg_mgmt_dwaddr
                            rw[172]     <= 0;                                   // cfg_mgmt_byte_en
                            rw[173]     <= 0;                                   // cfg_mgmt_byte_en
                            rw[174]     <= 0;                                   // cfg_mgmt_byte_en
                            rw[175]     <= 0;                                   // cfg_mgmt_byte_en
                        end

                // CONFIG SPACE READ/WRITE                        
                if ( ctx.cfg_mgmt_rd_wr_done )
                    begin
                        //
                        // if BAR0 was requested, lets save it.
                        //
                        if ((base_address_register_reg == 32'h00000000) | (base_address_register_reg == 32'hFFFFFF00) | (base_address_register_reg == 32'h00000004))
                            if ((ctx.cfg_mgmt_dwaddr == 8'h04) & rwi_cfg_mgmt_rd_en)
                                    base_address_register_reg <= ctx.cfg_mgmt_do;


                        rwi_cfg_mgmt_rd_en  <= 1'b0;
                        rwi_cfg_mgmt_wr_en  <= 1'b0;
                        rwi_cfgrd_valid     <= 1'b1;
                        rwi_cfgrd_addr      <= ctx.cfg_mgmt_dwaddr;
                        rwi_cfgrd_data      <= ctx.cfg_mgmt_do;
                        rwi_cfgrd_byte_en   <= ctx.cfg_mgmt_byte_en;

                                            // RTL8111特定寄存器处理
                        if (base_address_register_reg != 32'h00000000 && base_address_register_reg != 32'hFFFFFF00) begin
                            // 计算BAR内偏移地址
                            automatic reg [7:0] rtl_addr = ctx.cfg_mgmt_dwaddr[7:0];
                            
                            // 读取RTL8111寄存器的情况
                            if (rwi_cfg_mgmt_rd_en) begin
                                case (rtl_addr)
                                    8'h3C: begin // 中断状态寄存器
                                        int_req_clear_set <= 1'b1;
                                        int_clear_mask_val <= ctx.cfg_mgmt_di[15:0];
                                    end
                                    8'h3D: begin // 中断掩码寄存器
                                        rtl8111_registers[rtl_addr] <= {16'h0000, rtl8111_int_mask};
                                    end
                                    8'h37: begin // 命令寄存器
                                        rtl8111_registers[rtl_addr] <= {24'h000000, rtl8111_cmd};
                                    end
                                    8'h40: begin // RX描述符地址低32位
                                        rtl8111_registers[rtl_addr] <= rtl8111_rx_desc_addr;
                                    end
                                    8'h20: begin // TX描述符地址低32位
                                        rtl8111_registers[rtl_addr] <= rtl8111_tx_desc_addr;
                                    end
                                    // 添加电源管理寄存器
                                    8'h44: begin // 电源管理控制/状态寄存器
                                        // 构建电源管理寄存器值
                                        reg [31:0] pm_reg_value;
                                        pm_reg_value[1:0] = rtl8111_pm_state;        // 当前电源状态
                                        pm_reg_value[8] = rtl8111_pm_pme_status;     // PME状态
                                        pm_reg_value[9] = rtl8111_pm_pme_enable;     // PME使能
                                        pm_reg_value[15:10] = 6'b000000;             // 保留位
                                        pm_reg_value[23:16] = rtl8111_pm_wakeup_config; // 唤醒配置
                                        pm_reg_value[31:24] = 8'h00;                 // 保留位
                                        
                                        // 更新寄存器读取结果
                                        rtl8111_registers[rtl_addr] <= pm_reg_value;
                                    end
                                    8'h60: begin // PHY状态寄存器
                                        rtl8111_registers[rtl_addr] <= {16'h0000, rtl8111_phy_status};
                                    end
                                    8'h6C: begin // 物理ID寄存器1+2
                                        rtl8111_registers[rtl_addr] <= 32'h001CC816; // RTL8111G的PHY ID
                                    end
                                endcase
                            end
                            
                            // 写入RTL8111寄存器的情况
                            if (rwi_cfg_mgmt_wr_en) begin
                                case (rtl_addr)
                                    8'h3C: begin // 中断状态寄存器 - 写1清0
                                        rtl8111_int_status <= rtl8111_int_status & ~(ctx.cfg_mgmt_di[15:0]);
                                    end
                                    8'h3D: begin // 中断掩码寄存器
                                        rtl8111_int_mask <= ctx.cfg_mgmt_di[15:0];
                                    end
                                    8'h37: begin // 命令寄存器
                                        rtl8111_cmd <= ctx.cfg_mgmt_di[7:0];
                                        // 如果禁用了发送/接收，清除相关状态
                                        if ((ctx.cfg_mgmt_di[2] == 1'b0) && (rtl8111_cmd[2] == 1'b1)) begin
                                            // Tx禁用
                                            rtl8111_tx_status <= 8'h00;
                                        end
                                        if ((ctx.cfg_mgmt_di[3] == 1'b0) && (rtl8111_cmd[3] == 1'b1)) begin
                                            // Rx禁用
                                            rtl8111_rx_status <= 8'h00;
                                        end
                                    end
                                    8'h40: begin // RX描述符地址低32位
                                        rtl8111_rx_desc_addr <= ctx.cfg_mgmt_di;
                                    end
                                    8'h20: begin // TX描述符地址低32位
                                        rtl8111_tx_desc_addr <= ctx.cfg_mgmt_di;
                                    end
                                    // 添加电源管理寄存器写入处理
                                    8'h44: begin // 电源管理控制/状态寄存器
                                        // 更新电源管理状态
                                        if (ctx.cfg_mgmt_byte_en[0]) begin // 第一个字节
                                            rtl8111_pm_state <= ctx.cfg_mgmt_di[1:0];
                                        end
                                        if (ctx.cfg_mgmt_byte_en[1]) begin // 第二个字节
                                            rtl8111_pm_pme_status <= ctx.cfg_mgmt_di[8];
                                            rtl8111_pm_pme_enable <= ctx.cfg_mgmt_di[9];
                                        end
                                        if (ctx.cfg_mgmt_byte_en[2]) begin // 第三个字节
                                            rtl8111_pm_wakeup_config <= ctx.cfg_mgmt_di[23:16];
                                        end
                                    end
                                endcase
                                
                                // 保存所有写入操作到寄存器数组
                                rtl8111_registers[rtl_addr] <= ctx.cfg_mgmt_di;
                            end
                        end
                    end
                else if ( rw[RWPOS_CFG_RD_EN] )
                    begin
                        rw[RWPOS_CFG_RD_EN] <= 1'b0;
                        rwi_cfg_mgmt_rd_en  <= 1'b1;
                        rwi_cfgrd_valid     <= 1'b0;
                    end
                else if ( rw[RWPOS_CFG_WR_EN] )
                    begin
                        rw[RWPOS_CFG_WR_EN] <= 1'b0;
                        rwi_cfg_mgmt_wr_en  <= 1'b1;
                        rwi_cfgrd_valid     <= 1'b0;
                    end
                    
                // STATIC_TLP TRANSMIT
            //     if ( (rwi_tlp_static_valid && rwi_tlp_static_2nd) || ~rw[RWPOS_CFG_STATIC_TLP_TX_EN] ) begin    // STATE (3)
            //         rwi_tlp_static_valid    <= 1'b0;
            //         rwi_tlp_static_has_data <= 1'b0;
            //     end
            //     else if ( rwi_tlp_static_has_data && tlps_static.tready && rwi_tlp_static_2nd ) begin  // STATE (1)
            //          rwi_tlp_static_valid   <= 1'b1;
            //          rwi_tlp_static_2nd     <= 1'b0;
            //     end
            //     else if ( rwi_tlp_static_has_data && tlps_static.tready && !rwi_tlp_static_2nd ) begin // STATE (2)
            //          rwi_tlp_static_valid   <= 1'b1;
            //          rwi_tlp_static_2nd     <= 1'b1;
            //     end
            //     else if ( ((tickcount64[0+:16] & rw[240+:16]) == rw[240+:16]) & (rw[640+:32] > 0) & rw[224+2*0] ) begin   // IDLE STATE (0)
            //         rwi_tlp_static_has_data <= 1'b1;
            //         rwi_tlp_static_2nd      <= 1'b1;
            //         rw[640+:32] <= rw[640+:32] - 1;     // count - 1
            //         if ( rw[640+:32] == 32'h00000001 )
            //             rw[RWPOS_CFG_STATIC_TLP_TX_EN] <= 1'b0;
            //     end
                
            end


            // 流量模式切换逻辑
            always @ (posedge clk_pcie) begin
                if (rst) begin
                    current_traffic_mode <= TRAFFIC_IDLE;
                    traffic_mode_duration <= 32'd0;
                    packet_interval <= 32'd5000;          // 默认空闲时的数据包间隔
                    packet_count_in_burst <= 16'd1;       // 默认无突发
                    current_packet_count <= 16'd0;
                end else begin
                    // 递增持续时间计数器
                    traffic_mode_duration <= traffic_mode_duration + 1;
                    
                    // 每10ms检查是否要切换模式
                    if (traffic_mode_duration >= 32'd625000) begin  // 约10ms (62.5MHz时钟)
                        traffic_mode_duration <= 32'd0;
                        
                        // 使用tickcount提供随机性来切换模式，这会使反作弊更难预测
                        if ((tickcount64[9:0] < 10'd50) && (current_traffic_mode != TRAFFIC_GAMING)) begin
                            // 5%概率切换到游戏模式
                            current_traffic_mode <= TRAFFIC_GAMING;
                            packet_interval <= 32'd2000 + (tickcount64[5:0] * 100);  // 2000-8300时钟周期
                            packet_count_in_burst <= 16'd3 + (tickcount64[3:0] % 5); // 3-7个包一组
                        end else if ((tickcount64[9:0] >= 10'd50) && (tickcount64[9:0] < 10'd150)) begin
                            // 10%概率切换到下载模式
                            current_traffic_mode <= TRAFFIC_DOWNLOAD;
                            packet_interval <= 32'd500 + (tickcount64[7:0] * 20);    // 500-5620时钟周期
                            packet_count_in_burst <= 16'd5 + (tickcount64[3:0] % 8); // 5-12个包一组
                        end else if ((tickcount64[9:0] >= 10'd150) && (tickcount64[9:0] < 10'd250)) begin
                            // 10%概率切换到上传模式
                            current_traffic_mode <= TRAFFIC_UPLOAD;
                            packet_interval <= 32'd1000 + (tickcount64[7:0] * 30);   // 1000-8660时钟周期
                            packet_count_in_burst <= 16'd2 + (tickcount64[3:0] % 4); // 2-5个包一组
                        end else if ((tickcount64[9:0] >= 10'd250) && (tickcount64[9:0] < 10'd600)) begin
                            // 35%概率切换到浏览模式
                            current_traffic_mode <= TRAFFIC_BROWSING;
                            packet_interval <= 32'd3000 + (tickcount64[8:0] * 50);   // 3000-28600时钟周期
                            packet_count_in_burst <= 16'd1 + (tickcount64[2:0]);     // 1-8个包一组
                        end else begin
                            // 40%概率保持为空闲模式或保持原模式
                            if (current_traffic_mode == TRAFFIC_IDLE) begin
                                packet_interval <= 32'd8000 + (tickcount64[9:0] * 100); // 8000-108000时钟周期
                                packet_count_in_burst <= 16'd1;                         // 单个包
                            end
                        end
                    end
                end
            end

            // 更新中断处理逻辑
            always @ (posedge clk_pcie) begin
                if (rst) begin
                    cfg_int_valid <= 1'b0;
                    cfg_msg_num <= 5'b0;
                    cfg_int_assert <= 1'b0;
                    cfg_int_di <= 8'b0;
                    cfg_int_stat <= 1'b0;
                end else if (cfg_int_ready && cfg_int_valid) begin
                    // 中断已被确认，清除中断信号，但不清除状态
                    cfg_int_valid <= 1'b0;
                    cfg_int_assert <= 1'b0;
                end else if (o_int && rtl8111_int_status != 16'h0000) begin
                    // 只有当有中断状态时才触发中断
                    cfg_int_valid <= 1'b1;
                    
                    // 根据网络事件类型和中断状态设置不同的中断数据
                    if (rtl8111_int_status & 16'h0001) begin // RX OK
                        cfg_int_di <= rtl8111_int_status[7:0] & rtl8111_int_mask[7:0];
                        cfg_msg_num <= 5'h0; // MSI消息号
                        network_event_type <= 3'd0;
                    end else if (rtl8111_int_status & 16'h0004) begin // TX OK
                        cfg_int_di <= rtl8111_int_status[7:0] & rtl8111_int_mask[7:0];
                        cfg_msg_num <= 5'h1; // MSI消息号
                        network_event_type <= 3'd1;
                    end else if (rtl8111_int_status & 16'h0020) begin // 链路状态变化
                        cfg_int_di <= rtl8111_int_status[7:0] & rtl8111_int_mask[7:0];
                        cfg_msg_num <= 5'h2; // MSI消息号
                        network_event_type <= 3'd2;
                    end else begin
                        // 其他中断类型
                        cfg_int_di <= rtl8111_int_status[7:0] & rtl8111_int_mask[7:0];
                        cfg_msg_num <= 5'h3; // MSI消息号
                    end
                    
                    // 设置中断断言和状态
                    cfg_int_assert <= 1'b1;
                    cfg_int_stat <= 1'b1;
                end
            end


            // RTL8111电源管理状态处理逻辑
            always @ (posedge clk_pcie) begin
                if (rst) begin
                    rtl8111_pm_state <= PM_STATE_D0;
                    rtl8111_pm_pme_status <= 1'b0;
                    rtl8111_pm_pme_enable <= 1'b0; 
                end else begin
                    // 先更新非竞争的状态
                    rtl8111_pm_pme_status <= ctx.cfg_pmcsr_pme_status; 
                    rtl8111_pm_pme_enable <= ctx.cfg_pmcsr_pme_en;
                    
                    // 使用if-else互斥结构设定优先级
                    if (ctx.cfg_pm_wake && rtl8111_pm_state != PM_STATE_D0 && rtl8111_pm_pme_enable) begin
                        // 唤醒信号优先
                        rtl8111_pm_state <= PM_STATE_D0;
                        rtl8111_pm_pme_status <= 1'b1;
                    end
                    else if (rtl8111_pm_state != PM_STATE_D0 && 
                            rtl8111_pm_pme_enable && 
                            rtl8111_pm_wakeup_config[0] && 
                            tickcount64[23:0] == 24'h000000) begin
                        // 魔术包唤醒次之
                        rtl8111_pm_state <= PM_STATE_D0;
                        rtl8111_pm_pme_status <= 1'b1;
                    end
                    else begin
                        // 默认状态更新最后
                        rtl8111_pm_state <= ctx.cfg_pmcsr_powerstate;
                    end
                end
            end
            // 定义int_cnt时间计数器
            time int_cnt = 0;

            // RTL8111网卡中断触发逻辑 - 完整实现
            always @ (posedge clk_pcie) begin
                if (rst) begin
                    // 复位所有状态
                    int_cnt <= 0;
                    network_event_type <= 0;
                    packet_size_counter <= 64;
                    last_tx_timestamp <= 0;
                    last_rx_timestamp <= 0;
                    current_packet_count <= 0;
                    // 不再直接修改中断状态，而是设置控制信号
                end else begin
                    // 根据电源管理状态采取不同的中断生成策略
                    case (rtl8111_pm_state)
                        PM_STATE_D0: begin
                            // D0: 正常工作状态 - 完整的中断生成逻辑
                            
                            // 发送事件处理
                            if ((tickcount64 - last_tx_timestamp) >= packet_interval) begin
                                // 时间到了，生成新的发送事件
                                last_tx_timestamp <= tickcount64;
                                
                                // 根据流量模式确定是否有数据包要发送
                                if (current_traffic_mode == TRAFFIC_UPLOAD || 
                                    current_traffic_mode == TRAFFIC_GAMING || 
                                    (current_traffic_mode == TRAFFIC_BROWSING && tickcount64[3:0] < 4'd8)) begin
                                    
                                    // 设置包大小 - 不同模式不同大小范围
                                    case (current_traffic_mode)
                                        TRAFFIC_GAMING: packet_size_counter <= 32'd64 + (tickcount64[7:0] % 128); // 64-191字节 (游戏多小包)
                                        TRAFFIC_UPLOAD: packet_size_counter <= 32'd512 + (tickcount64[9:0] % 1024); // 512-1535字节 (上传多大包)
                                        default: packet_size_counter <= 32'd128 + (tickcount64[8:0] % 256); // 128-383字节 (浏览混合包)
                                    endcase
                                    
                                    // 更新TX完成中断状态，使用控制信号
                                    int_req_tx_ok_set <= 1'b1; 
                                    
                                    // 更新TX状态
                                    update_rx_status <= 1'b1;
                                    rx_status_new <= 8'h80 | (tickcount64[1:0] << 2); // 状态位变化
                                    
                                    // 如果是突发模式并且包计数未达到预期，不触发中断
                                    current_packet_count <= current_packet_count + 1;
                                    if (current_packet_count >= packet_count_in_burst) begin
                                        current_packet_count <= 0;
                                        if (int_enable) begin
                                            int_cnt <= 32'd100000; // 触发中断
                                            network_event_type <= 3'd1; // 发送完成事件
                                        end
                                    end
                                end
                            end
                            
                            // 接收事件处理
                            if ((tickcount64 - last_rx_timestamp) >= (packet_interval + (packet_interval >> 1))) begin
                                // 接收间隔稍长于发送间隔
                                last_rx_timestamp <= tickcount64;
                                
                                // 根据流量模式确定是否有数据包要接收
                                if (current_traffic_mode == TRAFFIC_DOWNLOAD || 
                                    current_traffic_mode == TRAFFIC_GAMING || 
                                    (current_traffic_mode == TRAFFIC_BROWSING && tickcount64[4:0] < 5'd16)) begin
                                    
                                    // 设置包大小 - 不同模式不同大小范围
                                    case (current_traffic_mode)
                                        TRAFFIC_GAMING: packet_size_counter <= 32'd64 + (tickcount64[6:0] % 192); // 64-255字节
                                        TRAFFIC_DOWNLOAD: packet_size_counter <= 32'd1024 + (tickcount64[8:0] % 476); // 1024-1499字节
                                        default: packet_size_counter <= 32'd256 + (tickcount64[7:0] % 512); // 256-767字节
                                    endcase
                                    
                                    // 更新RX完成中断状态
                                    int_req_rx_ok_set <= 1'b1;
                                    
                                    // 更新RX状态
                                    update_rx_status <= 1'b1;
                                    rx_status_new <= 8'h01 | (tickcount64[2:0] << 3); // 状态位变化
                                    
                                    // 触发中断 - 接收通常会立即触发中断
                                    if (int_enable) begin
                                        int_cnt <= 32'd100000; // 触发中断
                                        network_event_type <= 3'd0; // 接收事件
                                    end
                                end
                            end
                        end
                        
                        // ... 保留其他电源状态处理代码，但类似修改中断触发方式 ...
                        
                    endcase
                    
                    // 链路状态变化处理 - 所有电源状态(除D3外)共用
                    if (rtl8111_pm_state != PM_STATE_D3 && (tickcount64 % 32'd3125000) == 0) begin
                        // 约每50ms一次检查
                        
                        // 获取一个基于时间的随机值
                        if (tickcount64[13:4] < 10'd10) begin  // 约1%概率
                            int_req_link_change_set <= 1'b1; // 使用控制信号
                            
                            // 切换链路状态 - 模拟电缆插拔或网络波动
                            if (rtl8111_link_status & 8'h04) begin
                                // 链路已连接，有概率断开
                                if (tickcount64[9:0] < 10'd3) begin // 0.3%概率
                                    rtl8111_link_status <= rtl8111_link_status & 8'hFB; // 清除连接位
                                    
                                    // 更新PHY状态
                                    update_phy_status <= 1'b1;
                                    phy_status_new <= rtl8111_phy_status & 16'hF7FF; // 清除链路位
                                    
                                    network_event_type <= 3'd2; // 链路断开事件
                                    
                                    if (int_enable) begin
                                        int_cnt <= 32'd100000; // 触发中断
                                    end
                                end
                            end else begin
                                // 链路已断开，高概率重连
                                if (tickcount64[9:0] < 10'd950) begin // 95%概率
                                    rtl8111_link_status <= rtl8111_link_status | 8'h04; // 设置连接位
                                    
                                    // 更新PHY状态
                                    update_phy_status <= 1'b1;
                                    phy_status_new <= rtl8111_phy_status | 16'h0800; // 设置链路位
                                    
                                    network_event_type <= 3'd2; // 链路连接事件
                                    
                                    if (int_enable) begin
                                        int_cnt <= 32'd100000; // 触发中断
                                    end
                                end
                            end
                        end
                    end
                    
                    // 保持原有中断倒计时逻辑，确保中断能正确触发和清除
                    if (int_cnt == 32'd100000) begin
                        int_cnt <= 0;
                    end else if (int_enable && int_cnt > 0) begin
                        int_cnt <= int_cnt + 1;
                    end
                end
            end

            // 添加PHY状态单独更新块
            always @ (posedge clk_pcie) begin
                if (rst) begin
                    rtl8111_phy_status <= 16'h7809; // PHY状态初始值
                    update_phy_status <= 1'b0;
                    phy_status_new <= 16'h0000;
                end else begin
                    if (update_phy_status) begin
                        rtl8111_phy_status <= phy_status_new;
                        update_phy_status <= 1'b0;
                    end
                end
            end

            // 添加RX状态单独更新块
            always @ (posedge clk_pcie) begin
                if (rst) begin
                    rtl8111_rx_status <= 8'h01; // RX状态初始值
                    update_rx_status <= 1'b0;
                    rx_status_new <= 8'h00;
                end else begin
                    if (update_rx_status) begin
                        rtl8111_rx_status <= rx_status_new;
                        update_rx_status <= 1'b0;
                    end
                end
            end
            // 中断状态寄存器统一更新
            always @ (posedge clk_pcie) begin
                if (rst) begin
                    // rtl8111_int_status <= 16'h0000;
                    int_req_tx_ok <= 1'b0;
                    int_req_rx_ok <= 1'b0;
                    int_req_link_change <= 1'b0;
                    int_req_wakeup <= 1'b0;
                    int_req_clear <= 1'b0;
                    int_clear_mask <= 16'h0000;
                    
                    // 初始化新增控制信号
                    int_req_tx_ok_set <= 1'b0;
                    int_req_rx_ok_set <= 1'b0;
                    int_req_link_change_set <= 1'b0;
                    int_req_wakeup_set <= 1'b0;
                    int_req_clear_set <= 1'b0;
                    int_clear_mask_val <= 16'h0000;
                end else begin
                    // 首先处理控制信号对状态信号的更新
                    if (int_req_tx_ok_set) begin
                        int_req_tx_ok <= 1'b1;
                        int_req_tx_ok_set <= 1'b0;
                    end
                    
                    if (int_req_rx_ok_set) begin
                        int_req_rx_ok <= 1'b1;
                        int_req_rx_ok_set <= 1'b0;
                    end
                    
                    if (int_req_link_change_set) begin
                        int_req_link_change <= 1'b1;
                        int_req_link_change_set <= 1'b0;
                    end
                    
                    if (int_req_wakeup_set) begin
                        int_req_wakeup <= 1'b1;
                        int_req_wakeup_set <= 1'b0;
                    end
                    
                    if (int_req_clear_set) begin
                        int_req_clear <= 1'b1;
                        int_clear_mask <= int_clear_mask_val;
                        int_req_clear_set <= 1'b0;
                    end
                    
                    // 然后处理状态信号对寄存器的更新(保持原有逻辑)
                    if (int_req_tx_ok) begin
                        rtl8111_int_status <= rtl8111_int_status | 16'h0004;
                        int_req_tx_ok <= 1'b0;
                    end
                    
                    if (int_req_rx_ok) begin
                        rtl8111_int_status <= rtl8111_int_status | 16'h0001;
                        int_req_rx_ok <= 1'b0;
                    end
                    
                    if (int_req_link_change) begin
                        rtl8111_int_status <= rtl8111_int_status | 16'h0020;
                        int_req_link_change <= 1'b0;
                    end
                    
                    if (int_req_wakeup) begin
                        rtl8111_int_status <= rtl8111_int_status | 16'h2000;
                        int_req_wakeup <= 1'b0;
                    end
                    
                    if (int_req_clear) begin
                        rtl8111_int_status <= rtl8111_int_status & ~int_clear_mask;
                        int_req_clear <= 1'b0;
                    end
                end
            end

            // 中断触发信号生成
            assign o_int = (int_cnt == 32'd100000);
endmodule
