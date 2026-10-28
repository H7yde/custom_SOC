`timescale 1ns/1ps

// Compare every stored activation against the pre-pipeline CNN, allowing the
// two cores to accept input and complete at different times.
module tb_cnn_pipeline_equivalence;
    localparam integer MAX_FRAME_CYCLES = 2000000;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    reg [23:0] reference_data = 0, pipeline_data = 0;
    reg reference_valid = 0, pipeline_valid = 0;
    wire reference_ready, pipeline_ready;
    wire reference_result_valid, pipeline_result_valid;
    wire reference_class, pipeline_class;

    cnn_docx_reference_baseline reference_core (
        .clk(clk), .rst(rst), .pixel_data(reference_data),
        .pixel_valid(reference_valid), .pixel_ready(reference_ready),
        .result_valid(reference_result_valid), .classification(reference_class)
    );
    cnn_docx_reference pipeline_core (
        .clk(clk), .rst(rst), .pixel_data(pipeline_data),
        .pixel_valid(pipeline_valid), .pixel_ready(pipeline_ready),
        .result_valid(pipeline_result_valid), .classification(pipeline_class)
    );

    reg [23:0] human [0:1023], nonhuman [0:1023], frame [0:1023];
    reg armed = 0, seen_reference = 0, seen_pipeline = 0;
    reg saved_reference_class = 0, saved_pipeline_class = 0;
    integer tick = 0, started_at = 0;
    integer reference_cycles = 0, pipeline_cycles = 0;
    integer cases_passed = 0, activation_checks = 0;
    integer i, word_index;
    reg [31:0] random_state;

    always @(posedge clk) begin
        tick <= tick + 1;
        if (!rst && armed) begin
            if (reference_result_valid) begin
                if (seen_reference) $fatal(1, "Duplicate baseline result pulse");
                if ((reference_class !== 1'b0) && (reference_class !== 1'b1))
                    $fatal(1, "Unknown baseline classification");
                seen_reference <= 1;
                saved_reference_class <= reference_class;
                reference_cycles <= tick - started_at;
            end
            if (pipeline_result_valid) begin
                if (seen_pipeline) $fatal(1, "Duplicate pipeline result pulse");
                if ((pipeline_class !== 1'b0) && (pipeline_class !== 1'b1))
                    $fatal(1, "Unknown pipeline classification");
                seen_pipeline <= 1;
                saved_pipeline_class <= pipeline_class;
                pipeline_cycles <= tick - started_at;
            end
        end
    end

    task send_reference;
        input integer count;
        input integer gaps;
        integer index;
        begin
            for (index = 0; index < count; index = index + 1) begin
                @(negedge clk);
                reference_valid = 0;
                if (gaps && ((index % 13) == 0)) @(negedge clk);
                reference_data = frame[index];
                reference_valid = 1;
                @(posedge clk);
                while (reference_ready !== 1'b1) @(posedge clk);
            end
            @(negedge clk);
            reference_valid = 0;
        end
    endtask

    task send_pipeline;
        input integer count;
        input integer gaps;
        integer index;
        begin
            for (index = 0; index < count; index = index + 1) begin
                @(negedge clk);
                pipeline_valid = 0;
                if (gaps && ((index % 7) == 0)) @(negedge clk);
                pipeline_data = frame[index];
                pipeline_valid = 1;
                @(posedge clk);
                while (pipeline_ready !== 1'b1) @(posedge clk);
            end
            @(negedge clk);
            pipeline_valid = 0;
        end
    endtask

    task reset_cores;
        begin
            @(negedge clk);
            armed = 0;
            rst = 1;
            reference_valid = 0;
            pipeline_valid = 0;
            repeat (4) @(negedge clk);
            rst = 0;
            repeat (2) @(negedge clk);
            if ((reference_ready !== 1'b1) || (pipeline_ready !== 1'b1))
                $fatal(1, "Core did not return to capture mode after reset");
            if ((reference_result_valid !== 1'b0) || (pipeline_result_valid !== 1'b0))
                $fatal(1, "Stale result after reset");
        end
    endtask

    task compare_activations;
        input [255:0] case_name;
        integer index, errors;
        begin
            errors = 0;
            for (index = 0; index < 3600; index = index + 1) begin
                if (pipeline_core.c1[index] !== reference_core.c1[index]) begin
                    if (errors < 8) $display("%0s c1[%0d]: expected=%0d actual=%0d", case_name, index, $signed(reference_core.c1[index]), $signed(pipeline_core.c1[index]));
                    errors = errors + 1;
                end
                activation_checks = activation_checks + 1;
            end
            for (index = 0; index < 900; index = index + 1) begin
                if (pipeline_core.p1[index] !== reference_core.p1[index]) begin
                    if (errors < 8) $display("%0s p1[%0d]: expected=%0d actual=%0d", case_name, index, $signed(reference_core.p1[index]), $signed(pipeline_core.p1[index]));
                    errors = errors + 1;
                end
                activation_checks = activation_checks + 1;
            end
            for (index = 0; index < 676; index = index + 1) begin
                if (pipeline_core.c2[index] !== reference_core.c2[index]) begin
                    if (errors < 8) $display("%0s c2[%0d]: expected=%0d actual=%0d", case_name, index, $signed(reference_core.c2[index]), $signed(pipeline_core.c2[index]));
                    errors = errors + 1;
                end
                activation_checks = activation_checks + 1;
            end
            for (index = 0; index < 144; index = index + 1) begin
                if (pipeline_core.p2[index] !== reference_core.p2[index]) begin
                    if (errors < 8) $display("%0s p2[%0d]: expected=%0d actual=%0d", case_name, index, $signed(reference_core.p2[index]), $signed(pipeline_core.p2[index]));
                    errors = errors + 1;
                end
                activation_checks = activation_checks + 1;
            end
            for (index = 0; index < 64; index = index + 1) begin
                if (pipeline_core.c3[index] !== reference_core.c3[index]) begin
                    if (errors < 8) $display("%0s c3[%0d]: expected=%0d actual=%0d", case_name, index, $signed(reference_core.c3[index]), $signed(pipeline_core.c3[index]));
                    errors = errors + 1;
                end
                activation_checks = activation_checks + 1;
            end
            for (index = 0; index < 16; index = index + 1) begin
                if (pipeline_core.p3[index] !== reference_core.p3[index]) begin
                    if (errors < 8) $display("%0s p3[%0d]: expected=%0d actual=%0d", case_name, index, $signed(reference_core.p3[index]), $signed(pipeline_core.p3[index]));
                    errors = errors + 1;
                end
                activation_checks = activation_checks + 1;
            end
            if (errors) $fatal(1, "%0s: %0d activation mismatches", case_name, errors);
        end
    endtask

    task run_case;
        input [255:0] case_name;
        input integer expected_class; // -1 means compare only against baseline.
        input integer gaps;
        integer elapsed;
        begin
            @(negedge clk);
            seen_reference = 0;
            seen_pipeline = 0;
            started_at = tick;
            armed = 1;
            fork
                send_reference(1024, gaps);
                send_pipeline(1024, gaps);
            join
            elapsed = 0;
            while (!(seen_reference && seen_pipeline) && (elapsed < MAX_FRAME_CYCLES)) begin
                @(negedge clk);
                elapsed = elapsed + 1;
            end
            if (!(seen_reference && seen_pipeline))
                $fatal(1, "%0s timed out: baseline=%0b pipeline=%0b pipeline_state=%0d", case_name, seen_reference, seen_pipeline, pipeline_core.st);
            armed = 0;
            if (saved_pipeline_class !== saved_reference_class)
                $fatal(1, "%0s classification mismatch: expected=%0b actual=%0b", case_name, saved_reference_class, saved_pipeline_class);
            if ((expected_class >= 0) && (saved_pipeline_class !== expected_class[0]))
                $fatal(1, "%0s known classification mismatch", case_name);
            compare_activations(case_name);
            cases_passed = cases_passed + 1;
            $display("CNN EQUIVALENCE CASE PASS name=%0s class=%0d activations=5400 baseline_cycles=%0d pipeline_cycles=%0d", case_name, saved_pipeline_class, reference_cycles, pipeline_cycles);
            repeat (4) @(negedge clk);
            if ((reference_ready !== 1'b1) || (pipeline_ready !== 1'b1))
                $fatal(1, "Core failed to re-arm for a back-to-back frame");
        end
    endtask

    initial begin
        $readmemh("human_frames.mem", human);
        $readmemh("nonhuman_frame.mem", nonhuman);
        for (i = 0; i < 1024; i = i + 1) begin
            if ((^human[i] === 1'bx) || (^nonhuman[i] === 1'bx))
                $fatal(1, "Missing or invalid real image at pixel %0d", i);
        end
        reset_cores;

        for (i = 0; i < 1024; i = i + 1) frame[i] = human[i];
        run_case("human", 1, 0);
        for (i = 0; i < 1024; i = i + 1) frame[i] = nonhuman[i];
        run_case("nonhuman_back_to_back", 0, 1);
        // 255 must normalize to 16, rather than 15. This distinguishes the
        // exact integer division from a four-bit right shift approximation.
        for (i = 0; i < 1024; i = i + 1) frame[i] = 24'hffffff;
        run_case("white_255_corner", -1, 0);
        for (i = 0; i < 1024; i = i + 1) begin
            case (i % 8)
                0: frame[i] = 24'h000000;
                1: frame[i] = 24'h0f1011;
                2: frame[i] = 24'h7f8081;
                3: frame[i] = 24'hfdfeff;
                4: frame[i] = 24'hff0000;
                5: frame[i] = 24'h00ff00;
                6: frame[i] = 24'h0000ff;
                default: frame[i] = 24'hffffff;
            endcase
            if ((i % 8) == 3) frame[i] = 24'hfdfeff;
        end
        run_case("normalization_edges", -1, 1);
        random_state = 32'h12ab34cd;
        for (i = 0; i < 1024; i = i + 1) begin
            random_state = random_state ^ (random_state << 13);
            random_state = random_state ^ (random_state >> 17);
            random_state = random_state ^ (random_state << 5);
            frame[i] = random_state[23:0];
        end
        run_case("deterministic_random", -1, 1);

        // Abort a partial capture, then abort active convolution. A fresh
        // complete frame must overwrite all state after either reset.
        fork
            send_reference(127, 1);
            send_pipeline(127, 1);
        join
        reset_cores;
        fork
            send_reference(1024, 0);
            send_pipeline(1024, 0);
        join
        repeat (200) @(negedge clk);
        if ((reference_core.st == 0) || (pipeline_core.st == 0))
            $fatal(1, "Reset-under-compute test did not reach active convolution");
        reset_cores;
        for (i = 0; i < 1024; i = i + 1) frame[i] = 0;
        run_case("black_after_reset_recovery", -1, 0);
        $display("CNN PIPELINE EQUIVALENCE PASS cases=%0d activation_checks=%0d reset_abort_tests=2", cases_passed, activation_checks);
        $finish;
    end

    initial begin
        #200000000;
        $fatal(1, "Global CNN equivalence watchdog expired");
    end
endmodule
