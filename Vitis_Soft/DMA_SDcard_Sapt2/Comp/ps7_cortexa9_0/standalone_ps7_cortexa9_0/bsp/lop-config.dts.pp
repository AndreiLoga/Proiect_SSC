#line 2 "lop-config.dts"
/dts-v1/;
/ {
        compatible = "system-device-tree-v1,lop";
        lops {
                lop_0 {
                        compatible = "system-device-tree-v1,lop,load";
                        load = "assists/baremetal_validate_comp_xlnx.py";
                };

                lop_1 {
                    compatible = "system-device-tree-v1,lop,assist-v1";
                    node = "/";
                    outdir = "D:/000-UTCN/0-FACULTA_ANDREI/ANUL-3/SEM_1/SSC_P/Vitis_Soft/DMA_SDcard_Sapt2/Comp/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp";
                    id = "module,baremetal_validate_comp_xlnx";
                    options = "ps7_cortexa9_0 D:/0-Programe_Jocuri/Vivado2024.1/Vitis/2024.1/data/embeddedsw/lib/sw_services/xilffs_v5_2/src D:/000-UTCN/0-FACULTA_ANDREI/ANUL-3/SEM_1/SSC_P/Vitis_Soft/DMA_SDcard_Sapt2/.wsdata/.repo.yaml";
                };

        };
    };
