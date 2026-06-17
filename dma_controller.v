module dma_controller(clk,rst,control,bg,cpu_addr,cpu_wdata,cpu_rdata,io_rdata,io_wdata,hold,dma_addr,dma_data,status);
input clk,rst;
input [4:0]control;
input bg;
input [1:0]cpu_addr;
input [31:0]cpu_wdata;
output reg[31:0]cpu_rdata;
input [31:0]io_rdata;
output reg [31:0]io_wdata;
output reg hold;
output reg [15:0]dma_addr;
output reg[31:0]dma_data;
output reg [1:0]status;

reg [31:0]source_addr,dest_addr;
reg [31:0]buffer;
reg [15:0]length,counter;
reg br;
reg [3:0] pstate,nstate;

parameter [3:0] idle=4'b0000,
	cpu_write=4'b0001,
	cpu_read=4'b0010,
	bus_req=4'b0011,
	io_read=4'b0100,
	io_write=4'b0101,
	burst_trsf_mode=4'b0110,
	direct_trsf_mode=4'b0111,
	end_of_process=4'b1000;

// =========================================================================
// 1. SEQUENTIAL BLOCK: Handles Internal Registers, FSM State, and ALL Outputs
// =========================================================================
always@(posedge clk or posedge rst)
	begin
		if(rst)
			begin
				pstate      <= idle;
				source_addr <= 0;
				dest_addr   <= 0;
				length      <= 0;
				buffer      <= 0;
				counter     <= 0;
				// Synchronous/Asynchronous Reset for Outputs
				hold        <= 1'b0;
				dma_addr    <= 16'h0;
				dma_data    <= 32'h0;
				io_wdata    <= 32'h0;
				cpu_rdata   <= 32'h0;
				status      <= 2'b00;
				br          <= 1'b0;
			end
		else
			begin
				pstate <= nstate; // State Transition

				// --- CPU Configuration Management ---
				if(pstate == idle && !control[0])
					begin
						case(cpu_addr)
							2'b00: source_addr <= cpu_wdata;
							2'b01: dest_addr   <= cpu_wdata;
							2'b10: length      <= cpu_wdata[15:0];
							2'b11: buffer      <= cpu_wdata;
						endcase
					end
				
				// --- Internal Data & Counter Logic ---
				if (pstate == io_read && control[4:3] == 2'b01)
					buffer <= io_rdata;

				if ((pstate == io_write) || (pstate == direct_trsf_mode))
					counter <= counter + 1;
				else if (pstate == end_of_process)
					counter <= 0;

				// --- REGISTERED OUTPUT LOGIC (Based on current pstate) ---
				case(pstate)
					idle:
						begin
							status <= 2'b00;
							if(control[0] && control[2:1] != 2'b00 && control[2:1] != 2'b01)
								begin
									br   <= 1'b1;
									hold <= 1'b1;
								end
							else
								begin
									br   <= 1'b0;
									hold <= 1'b0;
								end
						end

					bus_req:
						begin
							hold <= 1'b1;
							br   <= 1'b1;
						end

					io_read:
						begin
							status   <= 2'b01;
							hold     <= 1'b1;
							dma_addr <= source_addr[15:0] + (counter * 4);
							dma_data <= buffer;
						end

					io_write:
						begin
							status   <= 2'b10;
							hold     <= 1'b1;
							dma_addr <= dest_addr[15:0] + (counter * 4);
							dma_data <= buffer;
							io_wdata <= buffer;
						end

					burst_trsf_mode:
						begin
							status <= 2'b10;
							hold   <= 1'b1;
						end

					direct_trsf_mode:
						begin
							status   <= 2'b10;
							hold     <= 1'b1;
							io_wdata <= io_rdata;
							dma_data <= io_rdata;
							dma_addr <= source_addr[15:0] + (counter * 4);
						end

					cpu_read:
						begin
							status <= 2'b01;
							case(cpu_addr)
								2'b00: cpu_rdata <= source_addr;
								2'b01: cpu_rdata <= dest_addr;
								2'b10: cpu_rdata <= length;
								2'b11: cpu_rdata <= buffer;
							endcase
						end

					cpu_write:
						begin
							status <= 2'b10;
						end

					end_of_process:
						begin
							br     <= 1'b0;
							status <= 2'b11;
							hold   <= 1'b0;
						end
				endcase
			end
	end

// =========================================================================
// 2. COMBINATIONAL BLOCK: Purely Computes Next State (No Output Assignments)
// =========================================================================
always@(*)
	begin
		nstate = pstate;
		case(pstate)
			idle:
				begin
					if(control[0])
						begin
							if(control[2:1]==2'b00)       nstate = cpu_read;
							else if(control[2:1]==2'b01)  nstate = cpu_write;
							else                          nstate = bus_req;
						end
					else
						nstate = idle;
				end
			bus_req:
				if(bg == 1'b1)
					nstate = (control[2:1] == 2'b10) ? io_read : io_write;
				else
					nstate = bus_req;
			io_read:
				if(bg) nstate = io_write;
			io_write:
				if(bg)
					begin
						if((counter >= length - 1) || control[4:3] == 2'b00)
							nstate = end_of_process;
						else if(counter[4:3] == 2'b01) 
							nstate = burst_trsf_mode;
						else
							nstate = direct_trsf_mode;
					end
				else
					nstate = bus_req;
			burst_trsf_mode:
				nstate = io_read;
			direct_trsf_mode:
				if(bg)
					nstate = (counter >= length - 1) ? end_of_process : direct_trsf_mode;
				else
					nstate = bus_req;
			cpu_read:
				nstate = end_of_process;
			cpu_write:
				nstate = end_of_process;
			end_of_process:
				nstate = idle;
			default:
				nstate = idle;
		endcase
	end

endmodule