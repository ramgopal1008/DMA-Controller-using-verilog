`timescale 1ns / 1ps

module dma_controller_tb;

    // --- Signals for the DMA ---
    reg clk;
    reg rst;
    reg [4:0] control;
    reg bg;
    reg [1:0] cpu_addr;
    reg [31:0] cpu_wdata;
    reg [31:0] io_rdata;

    wire [31:0] cpu_rdata, io_wdata, dma_data;
    wire hold;
    wire [15:0] dma_addr;
    wire [1:0] status;

    // --- Connect the DMA Controller ---
    dma_controller uut (
        .clk(clk), .rst(rst), .control(control), .bg(bg), 
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_rdata(cpu_rdata), 
        .io_rdata(io_rdata), .io_wdata(io_wdata), .hold(hold), 
        .dma_addr(dma_addr), .dma_data(dma_data), .status(status)
    );

    // --- Simple Clock: Toggles every 5ns (100MHz) ---
    always #5 clk = ~clk;

    initial begin
        // --- STEP 1: RESET ---
        clk = 0;
        rst = 1;
        bg = 0;
        control = 0;
        cpu_addr = 0;
        cpu_wdata = 0;
        io_rdata = 32'hAAAA_5555; // Dummy data to see it move
        
        #20 rst = 0; // Release reset
        #10;

        // --- STEP 2: PROGRAMMING BURST MODE (Mode 01) ---
        // We set the Source, Destination, and Length while control[0] is 0
		  
        @(negedge clk);
        cpu_addr = 2'b00; cpu_wdata = 32'h0100; // Source: 0x100
        @(negedge clk);
        cpu_addr = 2'b01; cpu_wdata = 32'h0500; // Dest:   0x500
        @(negedge clk);
        cpu_addr = 2'b10; cpu_wdata = 32'h0003;
		  @(negedge clk);
        cpu_addr = 2'b11; cpu_wdata = 32'hAB3;
		  // Length: 3 words

        // --- STEP 3: RUN BURST TRANSFER ---
        #10;
        control = 5'b01101; // Start bit=1, Mode=DMA, Type=Burst (01)
        
        wait(hold == 1);    // Wait for DMA to ask for bus
        #20 bg = 1;         // CPU grants the bus
        
        wait(status == 2'b11); // Wait for "End of Process"
        bg = 0;             // Reset bus grant
        control = 0;        // Reset start bit
        #50;

        // --- STEP 4: PROGRAMMING DIRECT MODE (Mode 10) ---
        @(negedge clk);
        cpu_addr = 2'b00; cpu_wdata = 32'h2000; // Source: 0x2000
        @(negedge clk);
        cpu_addr = 2'b01; cpu_wdata = 32'h3000; // Dest:   0x3000
        @(negedge clk);
        cpu_addr = 2'b10; cpu_wdata = 32'h0002;
		  @(negedge clk);
        cpu_addr = 2'b11; cpu_wdata = 32'hCAB3;
		  // Length: 2 words

        // --- STEP 5: RUN DIRECT TRANSFER ---
        #10;
        control = 5'b10101; // Start bit=1, Mode=DMA, Type=Direct (10)
        
        wait(hold == 1);
        #20 bg = 1;
        
        // Wait for it to finish
        wait(status == 2'b11);
        bg = 0;
		  
        control = 5'b00001;
		  #50;
		  
		  @(negedge clk);
        cpu_addr = 2'b00; cpu_wdata = 32'h2000; // Source: 0x2000
        @(negedge clk);
        cpu_addr = 2'b01; cpu_wdata = 32'h3000; // Dest:   0x3000
        @(negedge clk);
        cpu_addr = 2'b10; cpu_wdata = 32'h0002;
		  @(negedge clk);
        cpu_addr = 2'b11; cpu_wdata = 32'hCAB3;
		  // Length: 2 words

        // --- STEP 5: RUN DIRECT TRANSFER ---
        #10;
        control = 5'b10101;
		  
		  wait(hold == 1);
        #20 bg = 1;
        
        // Wait for it to finish
        wait(status == 2'b11);
        bg = 0;

        // --- STEP 6: FINISH ---
        #100;
        $display("All modes tested successfully!");
        $finish;
    end

    // This block prints what is happening to the console
    initial begin
        $monitor("Time=%0t | Status=%b | Addr=%h | Data=%h | BG=%b", 
                 $time, status, dma_addr, dma_data, bg);
    end

endmodule