## Need DMA Equiptment? I recommend shopping with [DMAPolice.com](https://dmapolice.com/)

# **Part 1: Foundational Concepts**

## **1. Introduction**

### **1.1 Purpose of the Guide**

This guide outlines a detailed roadmap for creating custom Direct Memory Access (DMA) firmware on FPGA-based devices, with the ultimate goal of accurately emulating PCIe hardware. Such emulation can serve a wide range of applications, including:

- **Hardware Development & Testing**  
  - Use FPGA-based emulation to replicate various hardware devices during development.  
  - Run system-level tests without the expense or availability constraints of specific donor hardware.

- **System Debugging & Diagnostics**  
  - Reproduce complex hardware behaviors in a controlled environment to pinpoint bugs or driver-related issues.  
  - Conduct trace analysis at the transaction layer (TLP) or memory-mapped I/O level.

- **Security & Malware Research**  
  - Investigate low-level PCIe vulnerabilities or advanced malware that interacts with hardware directly.  
  - Observe how certain device drivers behave when hardware signatures are partially or fully spoofed.

- **Hardware Emulation & Legacy Support**  
  - Replace aging hardware with an FPGA-based solution that mimics the original device’s PCIe IDs, BARs, and interrupts.  
  - Preserve legacy workflows on newer systems by emulating older or discontinued PCIe devices.

By following this guide, you will learn to:
1. **Gather** essential device information from a physical “donor” PCIe card.  
2. **Customize** FPGA firmware to present the same device/vendor IDs, BAR layouts, and capabilities.  
3. **Build & Configure** your development environment (Xilinx Vivado, Visual Studio Code, etc.).  
4. **Understand** the fundamentals of PCIe and DMA that are crucial to reliable device emulation.

> **Why This Matters**  
> Proper hardware emulation saves effort, reduces costs, and often allows for rapid iteration. FPGA-based cards can be reprogrammed on-the-fly, letting you adapt to multiple devices or firmware variations far more easily than with fixed hardware.

---

### **1.2 Target Audience**

This resource caters to a broad spectrum of professionals and enthusiasts:

- **Firmware Developers**  
  Interested in manipulating low-level system interactions, driver design, or advanced debugging of hardware/firmware stacks.

- **Hardware & Validation Engineers**  
  Seeking a controllable way to test system components with a wide variety of device profiles and conditions—without physically swapping PCIe cards every time.

- **Security Researchers**  
  Focused on analyzing the threat vectors introduced by DMA, exploring potential vulnerabilities in PCIe interactions, or performing safe sandbox emulations of malicious code.

- **FPGA Hobbyists & Makers**  
  Eager to expand their FPGA knowledge by building custom PCIe cores, learning advanced hardware description languages, and exploring real-world device enumeration.

---

### **1.3 How to Use This Guide**

The guide is split into three parts, each building on the last:

1. **Part 1: Foundational Concepts**  
   - Covers the prerequisite knowledge, environment setup, capturing donor device data, and making initial firmware adjustments.
2. **Part 2: Intermediate Concepts and Implementation**  
   - Delves into deeper firmware customization, TLP-level manipulations, debugging strategies, and how to refine an emulated device’s behavior to match or surpass its donor’s functionality.
3. **Part 3: Advanced Techniques and Optimization**  
   - Explores in-depth debugging tools, performance tuning, and best practices to ensure long-term maintainability of your FPGA-based DMA solutions.

> **Recommendation**: Complete Part 1 thoroughly before moving on. Skipping or partially implementing these foundational steps can lead to confusion and misconfigurations in later stages.

---

## **2. Key Definitions**

Having precise terminology is crucial for success in FPGA-based PCIe emulation. The following list expands on each relevant term:

1. **DMA (Direct Memory Access)**  
   - **Definition**: Hardware-mediated transfers between devices and system memory without CPU intervention.  
   - **Relevance**: Emulated devices heavily rely on DMA for throughput. Ensuring correct DMA configuration is central to a functional FPGA design.

2. **TLP (Transaction Layer Packet)**  
   - **Definition**: The fundamental communication unit in PCIe, encapsulating both header information and data payload.  
   - **Relevance**: Understanding TLP structure is vital if you plan to modify or analyze data at the PCIe transaction layer.

3. **BAR (Base Address Register)**  
   - **Definition**: Registers specifying the address ranges (memory or I/O) where a PCIe device’s resources appear in the system address space.  
   - **Relevance**: Accurately replicating a donor device’s BAR layout is key for correct driver loading and memory-mapped I/O handling.

4. **FPGA (Field-Programmable Gate Array)**  
   - **Definition**: A reconfigurable chip whose internal circuitry can be redesigned (via HDL) to implement custom hardware logic.  
   - **Relevance**: FPGAs let you quickly iterate on PCIe device designs, swapping out emulated devices with minimal hardware changes.

5. **MSI/MSI-X (Message Signaled Interrupts)**  
   - **Definition**: PCIe-compliant interrupt methods allowing devices to trigger CPU interrupts through in-band messages rather than dedicated lines.  
   - **Relevance**: Replicating donor interrupt behavior (especially the number of MSI vectors) can be critical for the driver that expects a specific interrupt mechanism.

6. **Device Serial Number (DSN)**  
   - **Definition**: A 64-bit unique identifier some PCIe devices use for licensing, authentication, or advanced driver checks.  
   - **Relevance**: Some drivers refuse to load or function unless the DSN matches the expected hardware.

7. **PCIe Configuration Space**  
   - **Definition**: A defined region (256 bytes for PCI or 4 KB for PCIe extended) detailing device ID, vendor ID, capabilities, and operational parameters.  
   - **Relevance**: Ensuring your FPGA device’s configuration space mirrors the donor’s (or includes the right subset) is essential to fool a host into treating it as the genuine article.

8. **Donor Device**  
   - **Definition**: The actual PCIe card from which you obtain data (IDs, class codes, etc.) for emulation.  
   - **Relevance**: The more data you accurately replicate, the closer your FPGA will behave to the original hardware in enumerations and function.

---

## **3. Device Compatibility**

### **3.1 Supported FPGA-Based Hardware**

1. **Squirrel (35T)**  
   - A cost-effective Artix-7–based FPGA board that supports basic DMA operations. Recommended if you’re new to FPGA-based PCIe development.

2. **Enigma-X1 (75T)**  
   - Offers more logic resources (LUTs, Block RAM) than a 35T, useful for moderate complexity tasks or extended debugging/tracing features.

3. **ZDMA (100T)**  
   - Targets higher performance applications with substantial FPGA resources for intensive data transfers or multiple concurrent DMA channels.

4. **Kintex-7**  
   - A robust, more premium FPGA family with advanced PCIe IP cores, typically used in demanding or large-scale emulation tasks.

> **Tip**: Always check the specific lane configuration (x1, x4, x8) and speed rating (Gen1, Gen2, etc.) for your FPGA card, verifying it meets or exceeds what your host motherboard can support.

### **3.2 PCIe Hardware Considerations**

- **IOMMU / VT-d**  
  - *Recommendation*: Temporarily disable to avoid restricted DMA regions, especially important if you need full memory access for thorough testing.

- **Kernel DMA Protection**  
  - *Windows VBS / Secure Boot*: In some cases, these features intercept or limit direct PCIe memory mapping.  
  - *Linux IOMMU or AppArmor/SELinux rules*: Adjust accordingly to ensure the FPGA can access the memory ranges it needs for emulation.

- **PCIe Slot Requirements**  
  - Choose a physical PCIe slot with enough lanes and confirm the BIOS is set to allocate those lanes appropriately.  
  - If you notice performance issues or partial enumeration, confirm your system is not forcing x1 operation on a physically larger slot.

### **3.3 System Requirements**

1. **Hardware**  
   - **CPU**: At least a quad-core from Intel or AMD for smooth Vivado synthesis and to manage OS overhead.  
   - **RAM**: 16 GB or more for comfortable Vivado usage, especially for multi-hour synthesis runs.  
   - **Storage**: 100 GB of SSD space recommended for faster project builds; mechanical HDDs can slow the build process drastically.  
   - **OS**: Windows 10/11 (64-bit) or a well-supported Linux distribution (e.g., Ubuntu LTS, RHEL/CentOS) to run Xilinx Vivado.

2. **Peripheral Devices**  
   - **JTAG Programmer**: (Xilinx Platform Cable USB II, Digilent HS3, or similar) needed to program your FPGA with the bitstream you create.  
   - **Dedicated Machine**: Strongly suggested if you’re altering BIOS-level settings (VT-d) or require an environment free of unexpected conflicts with existing PCIe devices.

---

## **4. Requirements**

### **4.1 Hardware**

1. **Donor PCIe Device**  
   - Purpose: You’ll extract the vendor/device ID, subsystem IDs, class code, BAR size, and capabilities.  
   - Examples: An older network interface card (NIC), a basic storage controller, or even a specialized PCIe device that you want to replicate/extend.

2. **DMA FPGA Card**  
   - Purpose: The actual hardware platform that runs the FPGA logic implementing the PCIe interface.  
   - Examples: Squirrel 35T, Enigma-X1, or ZDMA 100T boards.

3. **JTAG Programmer**  
   - Connects to the JTAG pins on your FPGA board, letting Vivado load the synthesized bitstream or debug firmware in real time.

### **4.2 Software**

1. **Xilinx Vivado Design Suite**  
   - Required for creating, synthesizing, and implementing the FPGA design.  
   - Download from [Xilinx](https://www.xilinx.com/support/download.html), ensuring you pick the correct version for your board’s IP requirements.

2. **Visual Studio Code**  
   - A flexible, cross-platform editor supporting Verilog/SystemVerilog with additional plugins.  
   - Helps maintain consistent code style, track changes, and streamline collaboration with version control (Git).

3. **PCILeech-FPGA**  
   - GitHub repository: [PCILeech-FPGA](https://github.com/ufrisk/pcileech-fpga).  
   - Offers baseline DMA designs for various FPGA boards, which you can further customize to replicate your donor device’s PCIe configuration.

4. **Arbor** (PCIe Device Scanner)  
   - A user-friendly GUI tool that provides in-depth analysis of connected PCIe devices.  
   - Alternatives: Telescan PE for traffic capture, or `lspci -vvv` in Linux for command-line introspection.

### **4.3 Environment Setup**

1. **Installing Vivado**  
   - Follow Xilinx’s official installer, selecting the appropriate FPGA family (Artix-7, Kintex-7, etc.).  
   - A Xilinx account may be required to download the Design Suite or access updates.

2. **Installing Visual Studio Code**  
   - Download from [Visual Studio Code](https://code.visualstudio.com/).  
   - Install recommended plugins: *Verilog-HDL/SystemVerilog* and a *Git* integration if you plan to maintain your project under source control.

3. **Cloning PCILeech-FPGA**  
   ```bash
   cd ~/Projects/
   git clone https://github.com/ufrisk/pcileech-fpga.git
   cd pcileech-fpga
   ```
   - Ensure you have Git installed and configured.

4. **Isolated Development Environment**  
   - Consider using a dedicated test machine (or a carefully configured dual-boot/VM) to reduce risk.  
   - This approach allows you to disable kernel DMA protections, IOMMU, or secure boot features more freely, without compromising a primary production system.

---

## **5. Gathering Donor Device Information**

Emulating a device effectively requires replicating its PCIe configuration space. That means capturing everything from device/vendor IDs to advanced capabilities.

### **5.1 Using Arbor for PCIe Device Scanning**

#### **5.1.1 Install & Launch Arbor**

1. **Obtain Arbor**  
   - Register and download from the official Arbor site.  
   - Install with administrator rights.

2. **Start Arbor**  
   - If prompted by UAC on Windows, confirm the application can run with elevated privileges.  
   - You should see an interface listing PCI/PCIe devices.

#### **5.1.2 Scan for Devices**

1. **Local System Tab**  
   - Navigate to the “Local System” or “Scan” area in Arbor.  
2. **Click “Scan”**  
   - Arbor enumerates all devices on your PCIe bus.  
3. **Identify the Donor**  
   - Match the brand name or vendor ID to your known donor hardware. If it’s not easily recognized, cross-reference with known IDs from hardware documentation.

#### **5.1.3 Extract Key Attributes**

Collect the following from Arbor’s detailed view:

- **Vendor ID / Device ID**: e.g., 0x8086 / 0x10D3 (Intel NIC).  
- **Subsystem Vendor ID / Subsystem ID**: e.g., 0x8086 / 0xA02F.  
- **Revision ID**: e.g., 0x01.  
- **Class Code**: e.g., 0x020000 for an Ethernet controller.  
- **BARs (Base Address Registers)**:  
  - For each BAR, note if it’s enabled, the memory size (256 MB, 64 KB, etc.), and whether it’s prefetchable or 32-bit/64-bit.  
- **Capabilities**:  
  - MSI or MSI-X details (number of interrupt vectors supported).  
  - Extended configuration or advanced power management features.  
- **Device Serial Number (DSN)** (if present):  
  - Some devices have a unique DSN field, especially if used for licensing or special driver checks.

> **Organization Tip**: Use a spreadsheet or structured document to save these values. This ensures you don’t overlook details like advanced features or extended capabilities.

---

## **6. Initial Firmware Customization**

With the donor’s PCIe attributes in hand, begin customizing your FPGA firmware to match those settings.

### **6.1 Modifying the PCIe Configuration Space**

Your FPGA design likely includes a top-level file that sets the PCIe configuration registers. For example, in the `pcileech-fpga` repository, look for a file such as `pcileech_pcie_cfg_a7.sv` or `pcie_7x_0_core_top.v`.

1. **Open File in VS Code**  
   - Search for lines defining `cfg_deviceid`, `cfg_vendorid`, `cfg_subsysid`, etc.

2. **Assign the Correct IDs**  
   ```verilog
   cfg_deviceid        <= 16'h10D3; // Example device ID
   cfg_vendorid        <= 16'h8086; // Example vendor ID
   cfg_subsysid        <= 16'h1234;
   cfg_subsysvendorid  <= 16'h5678;
   cfg_revisionid      <= 8'h01;
   cfg_classcode       <= 24'h020000; // Example for Ethernet
   ```
   - Replace these with the exact values from Arbor (or your donor’s datasheet).

3. **Insert DSN If Needed**  
   ```verilog
   cfg_dsn             <= 64'h0011223344556677;
   ```
   - Omit or set to 0 if your donor device doesn’t rely on a DSN.

4. **Save & Review**  
   - A single-digit error in any field could cause the OS to misidentify or reject the device. Double-check each line.

### **6.2 Consider BAR Configuration**

While some PCIe IP cores store BAR settings in the same SystemVerilog file, others rely on Vivado’s IP customization GUI:

- **Check how many BARs** your donor device uses (0 to 6).  
- **Set each BAR** (e.g., memory type, size, prefetchable, 64-bit vs. 32-bit).  
- If your donor has a large BAR region (e.g., 256 MB or bigger), ensure your FPGA board can accommodate it in the IP core settings.

---

## **7. Vivado Project Setup and Customization**

### **7.1 Generating Vivado Project Files**

To organize all design files properly, many repositories include Tcl scripts:

1. **Launch Vivado**  
   - Confirm you are using the correct version for your FPGA series (Artix-7, Kintex-7, etc.).

2. **Open Tcl Console**  
   - **Window > Tcl Console** in Vivado’s top menu.

3. **Navigate to Project Directory**  
   ```tcl
   cd C:/path/to/pcileech-fpga/pcileech-wifi-main/
   pwd
   ```
   - Confirm with `pwd` that the console is in the correct folder.

4. **Run the Generation Script**  
   ```tcl
   source vivado_generate_project_squirrel.tcl -notrace
   ```
   - If you’re using Enigma-X1 or ZDMA, run the corresponding script (e.g., `vivado_generate_project_enigma_x1.tcl`).

5. **Open the Generated Project**  
   - **File > Open Project**. Locate and select the `.xpr` (e.g., `pcileech_squirrel_top.xpr`).  
   - Check the **Project Manager** window for properly imported sources.

### **7.2 Customizing the PCIe IP Core**

In Vivado, you may find a PCIe IP core (e.g., `pcie_7x_0.xci`) under **Sources**:

1. **Right-Click -> Customize IP**  
   - Update vendor/device IDs, revision, and subsystem fields.  
   - Match your desired BAR configurations (sizes, memory type, etc.).

2. **Generate/Update the IP**  
   - Click **OK** or **Generate** to rebuild.  
   - Vivado might prompt you to upgrade or confirm dependencies if IP versions have changed.

3. **Lock the IP Core**  
   ```tcl
   set_property -name {IP_LOCKED} -value true -objects [get_ips pcie_7x_0]
   ```
   - This prevents future scripts from overwriting your manual changes inadvertently.

---

## **Additional Best Practices**

1. **Version Control** - *Highly Recommended*  
   - Commit your changes often (Git or another SCM).  
   - Tag or branch major changes so you can revert quickly if something breaks.

2. **Documentation**  
   - Keep a notebook, spreadsheet, or wiki summarizing donor device details, any special offsets, or capability quirks.  
   - Document each step you take in customizing your FPGA firmware.

3. **Testing on the Host**  
   - After generating a bitstream, program the FPGA, then check:  
     - **Windows**: Device Manager or `devcon.exe` to confirm the device enumerates with the correct IDs.  
     - **Linux**: `lspci -vvv` to see if the device identifies correctly, including BAR, Class Code, Subsystem, etc.

4. **Security Considerations**  
   - Disabling features like VT-d or Secure Boot can open up the system to vulnerabilities. Use a dedicated test rig or isolate the environment to maintain operational security.

5. **Where to Next?**  
   - In **Part 2**, you will learn to build on these basics with deeper TLP manipulation, partial reconfiguration strategies, firmware debugging, and any advanced ID spoofing or handshake emulations.

---

# **Part 2: Intermediate Concepts and Implementation**

---

## **8. Advanced Firmware Customization**

To precisely emulate your donor device, you must extend your basic configuration by aligning advanced PCIe parameters, fine-tuning BAR settings, and fully implementing power management and interrupt mechanisms. This ensures that your FPGA-based emulated device interacts with the host exactly as the original hardware would.

---

### **8.1 Configuring PCIe Parameters for Emulation**

Accurate PCIe emulation requires that your device’s link characteristics, capability pointers, and data transfer parameters (payload and read request sizes) match the donor device.

#### **8.1.1 Matching PCIe Link Speed and Width**

**Purpose:**  
The PCIe link speed (e.g., Gen1 at 2.5 GT/s, Gen2 at 5.0 GT/s, Gen3 at 8.0 GT/s) and the link width (e.g., x1, x4, x8) directly affect performance and compatibility. The donor’s parameters must be mirrored to ensure that the host system and drivers recognize and operate with the emulated device seamlessly.

**Steps:**

1. **Launch Vivado and Open Your Project:**  
   - Open the Vivado project (e.g., `pcileech_squirrel_top.xpr`) where your design is maintained.
   - Confirm that all source files are included and that the project hierarchy is intact.

2. **Access the PCIe IP Core Settings:**  
   - In the **Sources** pane, locate the PCIe IP core (typically named `pcie_7x_0.xci`).
   - Right-click the file and select **Customize IP** to open the configuration GUI.

3. **Set the Maximum Link Speed:**  
   - Navigate to the **Link Parameters** tab.  
   - Find the option labeled “Maximum Link Speed” and select the speed matching the donor device (e.g., 5.0 GT/s for Gen2).  
   - *Note:* Verify that both your FPGA board and the physical slot support the selected speed.

4. **Configure the Link Width:**  
   - In the same tab, locate “Link Width.”  
   - Choose the appropriate width (e.g., x4) as per the donor device.
   - *Note:* Options typically include 1, 2, 4, 8, or 16 lanes.

5. **Apply and Regenerate:**  
   - Click **OK** to save your changes. Vivado may prompt you to regenerate the IP core; allow the process to complete.
   - Finally, check the **Messages** window for any warnings or errors.

---

#### **8.1.2 Setting Capability Pointers**

**Purpose:**  
Capability pointers in the PCIe configuration space direct the host to locate extended capabilities (such as MSI/MSI‑X, power management, etc.). Matching these pointers ensures that the host accesses these capabilities exactly as it would with the donor device.

**Steps:**

1. **Open the Firmware Configuration File:**  
   - In Visual Studio Code, open the file (for example, `pcileech_pcie_cfg_a7.sv`) located under `pcileech-fpga/pcileech-wifi-main/src/`.

2. **Locate and Update the Capability Pointer Assignment:**  
   - Find the assignment statement for `cfg_cap_pointer`. For example:
     ```verilog
     cfg_cap_pointer <= 8'hXX; // Current default value
     ```
   - Replace `XX` with the correct donor offset (e.g., `8'h60` if the donor’s capability pointer is at offset 0x60):
     ```verilog
     cfg_cap_pointer <= 8'h60; // Set to donor's capability pointer at offset 0x60
     ```
   - *Verification:* Ensure that the capability structure is aligned on a 4-byte boundary as required by PCIe.

3. **Save the File and Comment Your Changes:**  
   - Save the file (Ctrl+S) and add inline comments for future reference.

---

#### **8.1.3 Adjusting Maximum Payload and Read Request Sizes**

**Purpose:**  
PCIe devices negotiate the maximum amount of data per transaction. The “Maximum Payload Size” (MPS) and “Maximum Read Request Size” (MRRS) must be set to values identical to the donor device to guarantee driver compatibility and optimal data throughput.

**Steps:**

1. **Configure in the PCIe IP Core:**  
   - In the IP customization GUI (found in the PCIe IP core), navigate to the **Device Capabilities** or **Capabilities** tab.
   - Set the **Maximum Payload Size Supported** (e.g., 256 bytes) and **Maximum Read Request Size Supported** (e.g., 512 bytes) to match the donor device.

2. **Update Firmware Constants:**  
   - Open `pcileech_pcie_cfg_a7.sv` in Visual Studio Code.
   - Locate the definitions for payload and read request sizes, for example:
     ```verilog
     max_payload_size_supported       <= 3'bZZZ; // Current value
     max_read_request_size_supported  <= 3'bWWW; // Current value
     ```
   - Replace with the correct binary encodings:
     - **Mapping (example):**
       - 128 bytes: `3'b000`
       - 256 bytes: `3'b001`
       - 512 bytes: `3'b010`
       - 1024 bytes: `3'b011`
       - 2048 bytes: `3'b100`
       - 4096 bytes: `3'b101`
     - For example, if the donor supports 256 bytes payload and 512 bytes read requests:
       ```verilog
       max_payload_size_supported       <= 3'b001; // 256 bytes
       max_read_request_size_supported  <= 3'b010; // 512 bytes
       ```

3. **Rebuild and Verify:**  
   - Save the changes, re-run synthesis, and check for consistency between the IP core settings and firmware constants.

---

### **8.2 Adjusting BARs and Memory Mapping**

BARs (Base Address Registers) determine which address spaces the device uses for memory or I/O. Correct BAR configuration is essential for driver operation and OS resource allocation.

#### **8.2.1 Setting BAR Sizes**

**Purpose:**  
Ensuring that each BAR is set to the correct size and type (32-bit vs. 64-bit; memory vs. I/O) guarantees that the host allocates the proper address space.

**Steps:**

1. **Customize BARs in the PCIe IP Core:**  
   - In Vivado, right-click on `pcie_7x_0.xci` and select **Customize IP**.
   - Navigate to the **BARs** tab.
   - For each BAR (BAR0–BAR5):
     - **Set the Size:** Select the size (e.g., 64 KB, 128 MB) as defined by the donor.
     - **Set the Type:** Choose between 32-bit or 64-bit memory addressing (or I/O space).
     - **Enable or Disable:** Enable only those BARs used by the donor.

2. **Synchronize with On-Chip Memory (if applicable):**  
   - If using Block RAM (BRAM) to back up the emulated BAR regions, open the associated BRAM IP core files (e.g., `bram_bar_zero4k.xci`) and ensure that the memory size corresponds to the BAR configuration.

3. **Save, Regenerate, and Verify:**  
   - Save your changes and allow Vivado to regenerate the IP core.
   - Review the **Messages** window for any configuration warnings.

---

#### **8.2.2 Defining BAR Address Spaces in Firmware**

**Purpose:**  
Implement logic to decode addresses targeting the BARs and route read/write operations correctly.

**Steps:**

1. **Open the BAR Controller Source File:**  
   - For example, open `pcileech_tlps128_bar_controller.sv` in Visual Studio Code.

2. **Implement Address Decoding Logic:**  
   - Use combinational logic to determine which BAR is being accessed:
     ```verilog
     always_comb begin
       if (bar_hit[0]) begin
         // Handle accesses to BAR0
       end else if (bar_hit[1]) begin
         // Handle accesses to BAR1
       end
       // Continue for additional BARs as necessary
     end
     ```
3. **Implement Read/Write Handling for Each BAR:**  
   - Within each branch, create case statements or conditional blocks to map specific address offsets to internal registers:
     ```verilog
     if (bar_hit[0]) begin
       case (addr_offset)
         16'h0000: data_out <= reg0;
         16'h0004: data_out <= reg1;
         // Add additional registers as needed
         default: data_out <= 32'h0;
       endcase
     end
     ```
4. **Save and Simulate:**  
   - Save your changes, then simulate the design (if possible) to verify that address decoding and data transfers are correctly handled.

---

#### **8.2.3 Handling Multiple BARs**

**Purpose:**  
If your device exposes multiple BARs, you must ensure that the logic for each BAR is isolated and that their address spaces do not conflict.

**Steps:**

1. **Separate BAR Logic:**  
   - Consider modularizing your code by separating logic for each BAR into distinct blocks or even separate modules (e.g., `bar0_controller.sv`, `bar1_controller.sv`).

2. **Validate Address Ranges:**  
   - Confirm that each BAR is allocated a unique, non-overlapping address range.  
   - Ensure that the sizes are aligned on power-of-two boundaries as required by the PCIe specification.

3. **Testing:**  
   - Perform both simulation (using test benches) and hardware testing (with tools such as `lspci -vvv` on Linux or Device Manager on Windows) to validate proper mapping and access.

---

### **8.3 Emulating Device Power Management and Interrupts**

Advanced emulation includes support for device power management states and interrupt handling. This is critical for driver functionality and overall system stability.

---

#### **8.3.1 Power Management Configuration**

**Purpose:**  
Enabling power management capabilities lets the device support various power states (D0 through D3), which is important for energy efficiency and proper OS behavior.

**Steps:**

1. **Enable Power Management in the PCIe IP Core:**  
   - In the IP customization window, navigate to the **Capabilities** tab and enable “Power Management.”  
   - Select the supported power states (e.g., D0 fully on, D1/D2 intermediate states, and D3 for low power).

2. **Implement PMCSR Logic in Firmware:**  
   - In your configuration file (e.g., `pcileech_pcie_cfg_a7.sv`), implement logic to handle writes to the Power Management Control/Status Register (PMCSR):
     ```verilog
     localparam PMCSR_ADDRESS = 12'h44; // Example address for PMCSR
     reg [15:0] pmcsr_reg;

     always @(posedge clk) begin
       if (cfg_write && cfg_address == PMCSR_ADDRESS) begin
         pmcsr_reg <= cfg_writedata[15:0];
         // Update internal power state based on pmcsr_reg[1:0]
       end
     end
     ```
   - *Note:* Update the device’s operational behavior if entering lower power states, as required by your donor.

3. **Test the Implementation:**  
   - Simulate power state transitions and verify that the PMCSR behaves as expected.

---

#### **8.3.2 MSI/MSI-X Configuration and Active Device Behavior**

**Understanding “Active Devices”:**  
In firmware parlance, an “active device” is one that regularly initiates DMA transfers and signals the host via interrupts when transfers complete. Rather than being “active” in a generic sense, these devices actively “ring the doorbell” to inform the CPU that data is ready. This concept is critical in systems where efficient interrupt signaling is key.

**MSI (Message Signaled Interrupts) vs. MSI-X:**  
- **MSI:** Uses the built-in interrupt interface provided by the Xilinx PCIe IP core.  
- **MSI-X:** Requires the firmware to manually construct and send a MEMWR64 (Memory Write 64-bit) TLP as the “doorbell” because the built-in interface does not support MSI-X natively.

**Steps for MSI (if using the built-in interface):**

1. **Configure MSI in the PCIe IP Core:**  
   - In the IP core customization, locate the **Interrupt** or **MSI/MSI-X** section.
   - Enable MSI and set the number of supported vectors (typically up to 32).

2. **Implement the Interrupt Interface in Firmware:**  
   - In your configuration file, wire up the interrupt signals as follows:
     ```verilog
     assign ctx.cfg_interrupt_di             = cfg_int_di;
     assign ctx.cfg_pciecap_interrupt_msgnum = cfg_msg_num;
     assign ctx.cfg_interrupt_assert         = cfg_int_assert;
     assign ctx.cfg_interrupt                = cfg_int_valid;
     assign ctx.cfg_interrupt_stat           = cfg_int_stat;
     ```
   - Then, include a process that asserts `cfg_int_valid` when an event occurs (for example, DMA completion):
     ```verilog
     always @(posedge clk_pcie) begin
       if (rst) begin
         cfg_int_valid <= 1'b0;
         cfg_msg_num   <= 5'b0;
         cfg_int_assert<= 1'b0;
         cfg_int_di    <= 8'b0;
         cfg_int_stat  <= 1'b0;
       end else if (cfg_int_ready && cfg_int_valid) begin
         cfg_int_valid <= 1'b0;
       end else if (o_int) begin
         cfg_int_valid <= 1'b0; // Adjust based on your interrupt generation timing
       end
     end

     // Example interrupt counter to generate periodic interrupts:
     reg [31:0] int_cnt;
     always @(posedge clk_pcie) begin
       if (rst)
         int_cnt <= 0;
       else if (int_cnt == 32'd100000)
         int_cnt <= 0;
       else if (int_enable)
         int_cnt <= int_cnt + 1;
     end
     assign o_int = (int_cnt == 32'd100000);
     ```

**Steps for MSI-X (Manual TLP Construction):**

1. **Manually Build the MSI-X TLP:**  
   - Because the Xilinx IP core interrupt interface does not support MSI-X, you must construct a MEMWR64 TLP that signals an interrupt.
   - Define the TLP fields as follows (modify as needed based on your donor’s specification):
     ```verilog
     // Define the header fields for a MEMWR64 TLP.
     wire [31:0] HDR_MEMWR64 = 32'b01000000_00000000_00000000_00000001;
     // Construct subsequent data words (ensure proper bit concatenation):
     wire [31:0] MWR64_DW2   = { _bs16(pcie_id), 8'b0, 8'b00001111 };
     wire [31:0] MWR64_DW3   = { i_addr[31:2], 2'b0 };
     wire [31:0] MWR64_DW4   = i_data;
     ```

2. **Integrate with TLP Output:**  
   - In your TLP transmit logic (e.g., within `pcileech_pcie_tlp_a7.sv`), assign the constructed TLP:
     ```verilog
     reg         msix_valid;
     reg         msix_has_data;
     reg [127:0] msix_tlp;

     assign tlps_static.tdata   = msix_tlp;
     assign tlps_static.tkeepdw = 4'hF;
     assign tlps_static.tlast   = 1'b1;
     assign tlps_static.tuser[0]= 1'b1;
     assign tlps_static.tvalid  = msix_valid;
     assign tlps_static.has_data= msix_has_data;

     always @(posedge clk_pcie) begin
       if (rst) begin
         msix_valid    <= 1'b0;
         msix_has_data <= 1'b0;
         msix_tlp      <= 128'b0;
       end else if (msix_valid) begin
         msix_valid <= 1'b0;
       end else if (msix_has_data && tlps_static.tready) begin
         msix_valid    <= 1'b1;
         msix_has_data <= 1'b0;
         msix_tlp      <= { MWR64_DW4, MWR64_DW3, MWR64_DW2, HDR_MEMWR64 };
       end else if (o_int) begin
         msix_has_data <= 1'b1;
       end
     end
     // Use a similar interrupt counter for periodic generation if needed.
     ```
   - *Verification:* Confirm that the assembled TLP conforms to the PCIe specification for a MEMWR64 packet. Use simulation and an Integrated Logic Analyzer (ILA) during hardware testing.

---

#### **8.3.3 Implementing Interrupt Handling Logic**

**Purpose:**  
Define clear conditions and a dedicated module for generating interrupts when required by events (e.g., DMA transfer completion). This is critical for an “active” device that signals the host frequently.

**Steps:**

1. **Define Interrupt Trigger Conditions:**  
   - Identify which events should generate an interrupt. These might include:
     - DMA transfer completion.
     - Data availability.
     - Error conditions.
   - Implement combinational or sequential logic to detect these events.

2. **Modularize the Interrupt Controller:**  
   - It is advisable to encapsulate interrupt logic in a separate module:
     ```verilog
     module interrupt_controller(
       input  wire clk,
       input  wire rst,
       input  wire event_trigger,
       output reg  msi_req
     );
       always @(posedge clk or posedge rst) begin
         if (rst)
           msi_req <= 1'b0;
         else if (event_trigger)
           msi_req <= 1'b1;
         else
           msi_req <= 1'b0;
       end
     endmodule
     ```
   - Integrate this module with your main firmware logic.

3. **Ensure Correct Timing:**  
   - Verify that interrupt assertions and de-assertions follow PCIe timing requirements.
   - Test with simulation and hardware debug tools (such as ILA) to confirm that the host receives interrupts appropriately.

---

### **8.4 What is “FULL EMU” vs. “DUMP EMU”?**

**Understanding the Terminology:**

- **DUMP EMU:**  
  A firmware approach that essentially “dumps” the donor device’s BAR and capability registers (often obtained via an Arbor scan) into the FPGA. This method replicates only the static configuration data.

- **FULL EMU:**  
  True full emulation replicates not only the static configuration (IDs, BARs, capabilities) but also the dynamic behavior of the donor device. This includes:
  - Generating correct TLPs (for reads, writes, completions, vendor-specific messages).
  - Handling power management transitions.
  - Implementing interrupt generation and proper “doorbell” signaling (especially with MSI‑X).
  - Supporting active DMA transfers and real-time responses as the donor would.

**Future Enhancements:**  
Planned updates may include detection methods that verify whether a firmware project is truly “FULL EMU” (with active dynamic behavior) versus a static “DUMP EMU.” For example, advanced testing on a Realtek-based NIC may be used as a benchmark.

---

## **10. Transaction Layer Packet (TLP) Emulation**

TLPs are the fundamental units of communication over PCIe. For a fully functional emulation, your design must not only replicate configuration space but also accurately generate and respond to TLPs as a real device would.

### **10.1 Understanding and Capturing TLPs**

#### **10.1.1 Learning the TLP Structure**

- **Header:**  
  Contains fields such as:
  - TLP Type (e.g., Memory Read, Memory Write, Config, Vendor-Defined)
  - Length, Requester ID, Tag, Address  
- **Data Payload:**  
  Present in transactions like Memory Write. Must honor the negotiated Maximum Payload Size.
- **CRC:**  
  Used for data integrity verification.

#### **10.1.2 Capturing TLPs from the Donor Device**

1. **Use a PCIe Protocol Analyzer:**  
   - Tools like Teledyne LeCroy analyzers or Xilinx ILA setups capture real-time TLPs.
2. **Capture and Analyze Transactions:**  
   - Monitor TLPs during normal operation to note header fields, sequence, and timing.
3. **Document Key Transactions:**  
   - Focus on initialization sequences, memory read/write exchanges, and vendor-specific messages.

---

### **10.2 Crafting Custom TLPs for Specific Operations**

#### **10.2.1 Implementing TLP Handling in Firmware**

1. **TLP Generation Functions:**  
   - In your TLP module (e.g., `pcileech_pcie_tlp_a7.sv`), create functions to assemble TLPs. For example:
     ```verilog
     function automatic [127:0] generate_tlp(
       input [15:0] requester_id,
       input [7:0]  tag,
       input [7:0]  length,
       input [31:0] address,
       input [31:0] data
     );
       // Construct and return a 128-bit TLP comprising header and payload.
     endfunction
     ```
2. **TLP Reception and Parsing:**  
   - Implement state machines to parse incoming TLPs and route them based on type (e.g., distinguishing between memory read and write).

3. **Completion Handling:**  
   - For memory read requests, generate completion TLPs with the requested data, ensuring adherence to PCIe timing and CRC requirements.

---

#### **10.2.2 Handling Different TLP Types**

1. **Memory Read Requests:**  
   - Parse the TLP header, read from the correct memory region, and send a completion TLP.
2. **Memory Write Requests:**  
   - Extract data payloads and write the data to emulated registers or memory blocks.
3. **Configuration Read/Write:**  
   - Access the configuration space registers accordingly.
4. **Vendor-Defined Messages:**  
   - Implement special handling if your donor device uses proprietary TLPs.

---

#### **10.2.3 Validating TLP Timing and Sequence**

1. **Simulation Testing:**  
   - Develop test benches that simulate TLP exchanges and verify the correctness of headers, payloads, and response timing.
2. **Hardware Debugging:**  
   - Use an ILA core to monitor TLP bus signals in real time.
3. **Compliance Verification:**  
   - Consider using PCIe compliance tools if available to verify that your TLP implementation meets specifications.

---

## **Conclusion**

By following these detailed procedures in Part 2, you now extend your emulation beyond static register replication. You are configuring critical PCIe link parameters, ensuring proper BAR and memory mapping, implementing full power management, and handling both MSI and MSI‑X interrupts. Furthermore, you have established a foundation for crafting and validating custom TLPs that enable a fully active, “FULL EMU” firmware solution—one that mirrors the dynamic behavior of the donor device.

**Key Takeaways:**

1. **Match Advanced PCIe Parameters Exactly:**  
   - Link speed, link width, capability pointers, and payload sizes must be identical to the donor’s.
2. **BAR Configuration and Address Decoding:**  
   - Correctly size and type your BARs, and implement robust address decoding logic.
3. **Interrupts – MSI vs. MSI‑X:**  
   - Use the built-in interrupt interface for MSI; manually construct MEMWR64 TLPs for MSI‑X.
4. **Active Device Behavior:**  
   - Emulate frequent DMA transfers and “doorbell” interrupt signaling to mirror real hardware activity.
5. **TLP Emulation:**  
   - Ensure that TLP generation, reception, and timing conform to PCIe standards for complete emulation.

In **Part 3**, we will build on these intermediate concepts with performance optimizations, extensive debugging techniques, and production-level best practices. Continue to validate each feature against the donor device’s specifications to achieve a truly indistinguishable emulation.
