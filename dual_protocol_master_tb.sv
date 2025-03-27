module dual_protocol_master_tb;
    // Clock and reset generation
    logic clk = 0;
    logic rst_n = 0;
    
    // Clock generation
    always #5 clk = ~clk;
    
    // Reset generation
    initial begin
        rst_n = 0;
        #100 rst_n = 1;
    end
    
    // Instantiate BFM interface
    dual_protocol_master_bfm bfm (
        .clk   (clk),
        .rst_n (rst_n)
    );
    
    // Command parser instance
    dual_protocol_command_parser parser;
    
    // Test stimulus
    initial begin
        // Wait for reset
        wait(rst_n);
        
        // Create parser instance
        parser = new("example_dual_protocol_commands.txt", bfm);
        
        // Parse and execute commands
        parser.parse_and_execute();
        
        // End simulation
        #1000;
        $display("Simulation completed successfully");
        $finish;
    end
    
    // Monitor for protocol violations
    property ahb_valid_size;
        @(posedge clk) bfm.ahb_hsel |-> bfm.ahb_hsize inside {3'b000, 3'b001, 3'b010};
    endproperty
    
    property axi_valid_size;
        @(posedge clk) bfm.axi_awvalid |-> bfm.axi_awsize inside {3'b000, 3'b001, 3'b010, 3'b011};
    endproperty
    
    assert property (ahb_valid_size)
        else $error("AHB size violation detected");
    
    assert property (axi_valid_size)
        else $error("AXI size violation detected");
    
    // Optional: Add coverage
    covergroup protocol_coverage @(posedge clk);
        ahb_size: coverpoint bfm.ahb_hsize {
            bins valid_sizes[] = {3'b000, 3'b001, 3'b010};
        }
        
        ahb_burst: coverpoint bfm.ahb_hburst {
            bins single = {3'b000};
            bins incr   = {3'b001};
            bins wrap4  = {3'b010};
            bins incr4  = {3'b011};
            bins wrap8  = {3'b100};
            bins incr8  = {3'b101};
            bins wrap16 = {3'b110};
            bins incr16 = {3'b111};
        }
        
        axi_burst: coverpoint bfm.axi_awburst {
            bins fixed = {2'b00};
            bins incr  = {2'b01};
            bins wrap  = {2'b10};
        }
    endgroup
    
    initial begin
        automatic protocol_coverage cov = new();
    end
    
endmodule
