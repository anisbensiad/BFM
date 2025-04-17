interface dual_protocol_master_bfm #(
    parameter AXI_DATA_WIDTH = 64,  // New parameter: supports 64 or 128 bits
    // Parameter validation
    parameter bit VALID_WIDTH = (AXI_DATA_WIDTH == 64 || AXI_DATA_WIDTH == 128) ? 1'b1 : 1'b0
) (
    input logic ahb_clk,
    input logic axi_clk,
    input logic rst_n,
    // AHB Interface
    output logic [31:0]             ahb_haddr,
    output logic [2:0]              ahb_hburst,
    output logic                    ahb_hmastlock,
    output logic [3:0]              ahb_hprot,
    output logic [2:0]              ahb_hsize,
    output logic [1:0]              ahb_htrans,
    output logic [31:0]             ahb_hwdata,
    output logic                    ahb_hwrite,
    output logic                    ahb_hsel,
    input  logic [31:0]             ahb_hrdata,
    input  logic                    ahb_hready,
    input  logic                    ahb_hresp,

    // AXI Interface
    output logic [31:0]             axi_awaddr,
    output logic [2:0]              axi_awprot,
    output logic [3:0]              axi_awregion,
    output logic [7:0]              axi_awlen,
    output logic [2:0]              axi_awsize,
    output logic [1:0]              axi_awburst,
    output logic [3:0]              axi_awcache,
    output logic [3:0]              axi_awqos,
    output logic                    axi_awvalid,
    input  logic                    axi_awready,
    output logic [AXI_DATA_WIDTH-1:0] axi_wdata,
    output logic [AXI_DATA_WIDTH/8-1:0] axi_wstrb,
    output logic                    axi_wlast,
    output logic                    axi_wvalid,
    input  logic                    axi_wready,
    output logic [31:0]             axi_araddr,
    output logic [2:0]              axi_arprot,
    output logic [3:0]              axi_arregion,
    output logic [7:0]              axi_arlen,
    output logic [2:0]              axi_arsize,
    output logic [1:0]              axi_arburst,
    output logic [3:0]              axi_arcache,
    output logic [3:0]              axi_arqos,
    output logic                    axi_arvalid,
    input  logic                    axi_arready,
    input  logic [AXI_DATA_WIDTH-1:0] axi_rdata,
    input  logic [1:0]              axi_rresp,
    input  logic                    axi_rlast,
    input  logic                    axi_rvalid,
    output logic                    axi_rready,
    input  logic [1:0]              axi_bresp,
    input  logic                    axi_bvalid,
    output logic                    axi_bready
    );
    
    

    // Compile-time check for valid AXI_DATA_WIDTH
    initial begin
        assert(VALID_WIDTH) else
            $fatal(1, "AXI_DATA_WIDTH must be either 64 or 128!");
    end


 assign  ahb_hmastlock =0;
 assign  ahb_hprot =0;


    // AHB Tasks 
    task automatic ahb_write(
        input logic [31:0] address,
        input logic [31:0] data,
        input logic [2:0]  burst,
        input logic [2:0]  size
    );
        // Setup phase
        @(posedge ahb_clk);
        ahb_hsel   = 1'b1;
        ahb_haddr  = address;
        ahb_hsize  = size;
        ahb_hburst = burst;
        ahb_htrans = 2'b10;  // Non-sequential
        ahb_hwrite = 1'b1;
        
        // Wait for ready
        while (!ahb_hready) @(posedge ahb_clk);
        
        // Data phase
        ahb_hwdata = data;
        @(posedge ahb_clk);
        
        // Reset control signals
        ahb_hsel   = 1'b0;
        ahb_htrans = 2'b00;  // IDLE
        ahb_hwrite = 1'b0;
    endtask

    task  ahb_read(
            input  logic [31:0] address,
            output logic [31:0] data,
            input  logic [2:0]  burst,
            input  logic [2:0]  size
        );
        // Setup phase
        @(posedge ahb_clk);
        begin

            ahb_hsel   = 1'b1;
            ahb_haddr  = address;
            ahb_hsize  = size;
            ahb_hburst = burst;
            ahb_htrans = 2'b10;  // Non-sequential
            ahb_hwrite = 1'b0;

            // Wait for ready
            while (!ahb_hready) @(posedge ahb_clk);

            // Data phase
            @(posedge ahb_clk);
            #1ps
            data = ahb_hrdata;

            // Reset control signals
            ahb_hsel   = 1'b0;
            ahb_htrans = 2'b00;  // IDLE
        end

    endtask

    // Modified AXI Tasks for configurable width
    task automatic axi_write(
        input logic [31:0] address,
        input logic [AXI_DATA_WIDTH-1:0] data,
        input logic [7:0]  len,
        input logic [1:0]  burst_type
    );
        // Address Phase
        @(posedge axi_clk);
        axi_awvalid = 1'b1;
        axi_awaddr  = address;
        axi_awlen   = len;
        axi_awburst = burst_type;
        axi_awsize  = (AXI_DATA_WIDTH == 128) ? 3'b100 : 3'b011;  // 16 bytes for 128-bit, 8 bytes for 64-bit
        
        while (!axi_awready) @(posedge axi_clk);
        //@(posedge axi_clk);
        axi_awvalid = 1'b0;
        
        // Data Phase
        axi_wvalid = 1'b1;
        axi_wdata  = data;
        axi_wstrb  = {(AXI_DATA_WIDTH/8){1'b1}};  // All bytes enabled
        axi_wlast  = 1'b1;
        
        while (!axi_wready) @(posedge axi_clk);
        //@(posedge axi_clk);
        axi_wvalid = 1'b0;
        
        // Response Phase
        axi_bready = 1'b1;
        while (!axi_bvalid) @(posedge axi_clk);
        //@(posedge axi_clk);
        axi_bready = 1'b0;
    endtask

 task automatic axi_read(
        input  logic [31:0] address,
        output logic [AXI_DATA_WIDTH-1:0] data[$],  // Now returns a queue of data
        input  logic [7:0]  len,
        input  logic [1:0]  burst_type
    );
        logic [AXI_DATA_WIDTH-1:0] current_data;
        
        // Clear the data queue
        data.delete();
        
        // Address Phase
        @(posedge axi_clk);
        axi_arvalid = 1'b1;
        axi_araddr  = address;
        axi_arlen   = len;
        axi_arburst = burst_type;
        axi_arsize  = (AXI_DATA_WIDTH == 128) ? 3'b100 : 3'b011;  // 16 bytes for 128-bit, 8 bytes for 64-bit
        
        while (!axi_arready) @(posedge axi_clk);
        //@(posedge axi_clk);
        axi_arvalid = 1'b0;
        
        // Data Phase
        axi_rready = 1'b1;
        
        // Collect all beats of data
        do begin
            @(posedge axi_clk);
            if (axi_rvalid) begin
                current_data = axi_rdata;
                data.push_back(current_data);
            end
        end while (!axi_rlast || !axi_rvalid);
        
        @(posedge axi_clk);
        axi_rready = 1'b0;
    endtask


    // Initial block for signal initialization
    initial begin
        // Initialize AHB signals
        ahb_hsel   = 1'b0;
        ahb_haddr  = '0;
        ahb_hsize  = '0;
        ahb_hburst = '0;
        ahb_htrans = '0;
        ahb_hwrite = 1'b0;
        ahb_hwdata = '0;

        // Initialize AXI signals
        axi_awvalid = 1'b0;
        axi_awaddr  = '0;
        axi_awlen   = '0;
        axi_awsize  = '0;
        axi_awburst = '0;
        axi_wvalid  = 1'b0;
        axi_wdata   = '0;
        axi_wstrb   = '0;
        axi_wlast   = 1'b0;
        axi_bready  = 1'b0;
        axi_arvalid = 1'b0;
        axi_araddr  = '0;
        axi_arlen   = '0;
        axi_arsize  = '0;
        axi_arburst = '0;
        axi_rready  = 1'b0;
    end

endinterface
