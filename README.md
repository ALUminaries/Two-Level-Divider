# Two-Level-Divider
This repository contains source code for a VHDL implementation of the high-precision integer division algorithm using a two-level hardware structure proposed in the paper "[High-Precision Priority Encoder Based Integer Division Algorithm](https://ieeexplore.ieee.org/document/9531809)." All components are generalized such that only generics need modified to adapt the hardware to different bit precisions.

### Files
- For implementation and on-board testing, all files in `src` and subdirectories are required.
  - Technically, not all of the small encoder components in `src/Base Encoders` are needed depending on bit precision, but if you are switching between bit precisions it is recommended to simply import all of them, as `priority_encoder_generic` will only instantiate the necessary components.
  - To adjust for different bit precisions, modify the generics in the top-level file.
- For synthesis and simulation *only*, the files in `src/XCVR` are not required. Everything else is as stated above.

### Other
- Some useful resources for testing can be found [here](https://github.com/ALUminaries/Two-Level-Multiplier).
- The code provided implements our [serial transceiver, which can be found here](https://github.com/ALUminaries/Serial-Transceiver).

### Hardware Block Diagram
![image](https://github.com/ALUminaries/Two-Level-Divider/assets/16062019/f8893681-b5e7-47b6-b0fc-2e83da614538)


