slangc src/shaders/fullscreen.slang -target spirv -profile spirv_1_4 -emit-spirv-directly -fvk-use-entrypoint-name -entry vertMain -entry fragMain -o build/lin/fullscreen.spv
slangc src/shaders/default.slang -target spirv -profile spirv_1_4 -emit-spirv-directly -fvk-use-entrypoint-name -entry vertMain -entry fragMain -o build/lin/default.spv
slangc src/shaders/imgui_vert.slang -target spirv -profile spirv_1_4 -emit-spirv-directly -fvk-use-entrypoint-name -entry main -o build/lin/imgui_vert.spv
slangc src/shaders/imgui_frag.slang -target spirv -profile spirv_1_4 -emit-spirv-directly -fvk-use-entrypoint-name -entry main -o build/lin/imgui_frag.spv
