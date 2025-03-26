class dual_protocol_command_parser;
    // File handle
    int file_handle;
    string filename;
    
    // Reference to BFM using a virtual interface handle
    virtual dual_protocol_master_bfm bfm;
    
    // Enumerated types for command parsing
    typedef enum {
        AHB,
        AXI,
        WAIT
    } protocol_t;
    
    typedef enum {
        CMD_WRITE,
        CMD_READ,
        CMD_BURST_WRITE,
        CMD_BURST_READ,
        CMD_WAIT
    } command_t;
    
    // Local copies of BFM enums to avoid hierarchical references
    typedef enum logic [2:0] {
        BYTE     = 3'b000,
        HALFWORD = 3'b001,
        WORD     = 3'b010
    } local_ahb_size_t;

    typedef enum logic [2:0] {
        SINGLE  = 3'b000,
        INCR    = 3'b001,
        INCR4   = 3'b011,
        INCR8   = 3'b101,
        INCR16  = 3'b111,
        WRAP4   = 3'b010,
        WRAP8   = 3'b100,
        WRAP16  = 3'b110
    } local_ahb_burst_t;

    typedef enum logic [1:0] {
        AXI_FIXED = 2'b00,
        AXI_INCR  = 2'b01,
        AXI_WRAP  = 2'b10
    } local_axi_burst_t;

    // Constructor
    function new(string filename, virtual dual_protocol_master_bfm bfm);
        this.filename = filename;
        this.bfm = bfm;
    endfunction
    
    // Parse and execute commands
    task automatic parse_and_execute();
        string line;
        string command_tokens[$];
        
        // Open the command file
        file_handle = $fopen(filename, "r");
        if (file_handle == 0) begin
            $error("Could not open file %s", filename);
            return;
        end
        
        // Read and process each line
        while (!$feof(file_handle)) begin
            protocol_t protocol;
            command_t  command;
            
            // Read line and skip empty lines or comments
            if ($fgets(line, file_handle)) begin
                line = strip_comments(line);
                if (line.len() == 0) continue;
                
                // Split line into tokens
                tokenize(line, command_tokens);
                if (command_tokens.size() == 0) continue;
                
                // Parse protocol and command
                if (parse_protocol_and_command(command_tokens, protocol, command)) begin
                    case (protocol)
                        AHB: process_ahb_command(command, command_tokens);
                        AXI: process_axi_command(command, command_tokens);
                        WAIT: process_wait_command(command_tokens);
                    endcase
                end
            end
        end
        
        $fclose(file_handle);
    endtask
    
    // Helper functions
    protected function string strip_comments(string line);
        int comment_pos = line.find("#");
        if (comment_pos != -1)
            return line.substr(0, comment_pos-1);
        return line;
    endfunction
    
    protected function void tokenize(string line, ref string tokens[$]);
        string token;
        int pos = 0;
        tokens.delete();
        
        // Split line into tokens
        while ($sscanf(line.substr(pos, line.len()-1), "%s%n", token, pos) == 1) begin
            tokens.push_back(token);
        end
    endfunction
    
    // Parse protocol and command type
    protected function bit parse_protocol_and_command(
        string tokens[$],
        output protocol_t protocol,
        output command_t  command
    );
        if (tokens.size() < 2) return 0;
        
        // Parse protocol
        case (tokens[0].toupper())
            "AHB": protocol = AHB;
            "AXI": protocol = AXI;
            "WAIT": begin
                protocol = WAIT;
                return 1;
            end
            default: begin
                $error("Invalid protocol: %s", tokens[0]);
                return 0;
            end
        endcase
        
        // Parse command
        case (tokens[1].toupper())
            "WRITE": command = CMD_WRITE;
            "READ":  command = CMD_READ;
            "BURST_WRITE": command = CMD_BURST_WRITE;
            "BURST_READ":  command = CMD_BURST_READ;
            default: begin
                $error("Invalid command: %s", tokens[1]);
                return 0;
            end
        endcase
        
        return 1;
    endfunction
    
    // Process AHB commands
    protected task process_ahb_command(command_t command, string tokens[$]);
        logic [31:0] address;
        logic [31:0] data;
        local_ahb_burst_t burst_type = SINGLE;
        local_ahb_size_t size = WORD;
        
        if (tokens.size() < 3) begin
            $error("Invalid AHB command format");
            return;
        end
        
        // Parse address
        void'($sscanf(tokens[2], "%h", address));
        
        case (command)
            CMD_WRITE: begin
                if (tokens.size() < 4) begin
                    $error("Invalid AHB WRITE command format");
                    return;
                end
                
                // Parse data
                void'($sscanf(tokens[3], "%h", data));
                
                // Parse optional burst type
                if (tokens.size() > 4) begin
                    burst_type = parse_ahb_burst_type(tokens[4]);
                end
                
                // Parse optional size
                if (tokens.size() > 5) begin
                    size = parse_ahb_size(tokens[5]);
                end
                
                // Execute write
                bfm.ahb_write(address, data, burst_type, size);
            end
            
            CMD_READ: begin
                logic [31:0] read_data;
                
                // Parse optional burst type
                if (tokens.size() > 3) begin
                    burst_type = parse_ahb_burst_type(tokens[3]);
                end
                
                // Parse optional size
                if (tokens.size() > 4) begin
                    size = parse_ahb_size(tokens[4]);
                end
                
                // Execute read
                bfm.ahb_read(address, read_data, burst_type, size);
                $display("AHB Read Data: 0x%h from address 0x%h", read_data, address);
            end
            
            default: $error("Unsupported AHB command: %s", tokens[1]);
        endcase
    endtask
    
    // Process AXI commands
    protected task process_axi_command(command_t command, string tokens[$]);
        logic [31:0] address;
        logic [63:0] data;
        local_axi_burst_t burst_type = AXI_INCR;
        logic [7:0] len = 0;
        
        if (tokens.size() < 3) begin
            $error("Invalid AXI command format");
            return;
        end
        
        // Parse address
        void'($sscanf(tokens[2], "%h", address));
        
        case (command)
            CMD_WRITE: begin
                if (tokens.size() < 4) begin
                    $error("Invalid AXI WRITE command format");
                    return;
                end
                
                // Parse data
                void'($sscanf(tokens[3], "%h", data));
                
                // Parse optional burst type
                if (tokens.size() > 4) begin
                    burst_type = parse_axi_burst_type(tokens[4]);
                end
                
                // Parse optional length
                if (tokens.size() > 5) begin
                    void'($sscanf(tokens[5], "%d", len));
                end
                
                // Execute write
                bfm.axi_write(address, data, len, burst_type);
            end
            
            CMD_READ: begin
                logic [63:0] read_data;
                
                // Parse optional burst type
                if (tokens.size() > 3) begin
                    burst_type = parse_axi_burst_type(tokens[3]);
                end
                
                // Parse optional length
                if (tokens.size() > 4) begin
                    void'($sscanf(tokens[4], "%d", len));
                end
                
                // Execute read
                bfm.axi_read(address, read_data, len, burst_type);
                $display("AXI Read Data: 0x%h from address 0x%h", read_data, address);
            end
            
            default: $error("Unsupported AXI command: %s", tokens[1]);
        endcase
    endtask
    
    // Process wait command
    protected task process_wait_command(string tokens[$]);
        int cycles;
        
        if (tokens.size() < 2) begin
            $error("Invalid WAIT command format");
            return;
        end
        
        void'($sscanf(tokens[1], "%d", cycles));
        repeat(cycles) @(posedge bfm.clk);
    endtask
    
    // Helper function to parse AHB burst type
    protected function local_ahb_burst_t parse_ahb_burst_type(string burst_str);
        case (burst_str.toupper())
            "SINGLE": return SINGLE;
            "INCR":   return INCR;
            "INCR4":  return INCR4;
            "INCR8":  return INCR8;
            "INCR16": return INCR16;
            "WRAP4":  return WRAP4;
            "WRAP8":  return WRAP8;
            "WRAP16": return WRAP16;
            default: begin
                $error("Invalid AHB burst type: %s", burst_str);
                return SINGLE;
            end
        endcase
    endfunction
    
    // Helper function to parse AHB size
    protected function local_ahb_size_t parse_ahb_size(string size_str);
        case (size_str.toupper())
            "BYTE":     return BYTE;
            "HALFWORD": return HALFWORD;
            "WORD":     return WORD;
            default: begin
                $error("Invalid AHB size: %s", size_str);
                return WORD;
            end
        endcase
    endfunction
    
    // Helper function to parse AXI burst type
    protected function local_axi_burst_t parse_axi_burst_type(string burst_str);
        case (burst_str.toupper())
            "FIXED": return AXI_FIXED;
            "INCR":  return AXI_INCR;
            "WRAP":  return AXI_WRAP;
            default: begin
                $error("Invalid AXI burst type: %s", burst_str);
                return AXI_INCR;
            end
        endcase
    endfunction
    
endclass
