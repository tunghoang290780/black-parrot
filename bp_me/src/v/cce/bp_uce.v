
module bp_uce
  import bp_common_pkg::*;
  import bp_common_aviary_pkg::*;
  import bp_cce_pkg::*;
  import bp_common_cfg_link_pkg::*;
  import bp_me_pkg::*;
  #(parameter bp_params_e bp_params_p = e_bp_inv_cfg
   ,parameter assoc_p = 8
   ,parameter sets_p = 64
   ,parameter block_width_p = 512
   ,parameter fill_width_p = 512

    `declare_bp_proc_params(bp_params_p)
    `declare_bp_me_if_widths(paddr_width_p, cce_block_width_p, lce_id_width_p, lce_assoc_p)

    , localparam stat_info_width_lp = `bp_cache_stat_info_width(assoc_p)

    , localparam bank_width_lp = block_width_p / assoc_p
    , localparam num_dwords_per_bank_lp = bank_width_lp / dword_width_p
    , localparam byte_offset_width_lp  = `BSG_SAFE_CLOG2(bank_width_lp>>3)
    // Words per line == associativity
    , localparam bank_offset_width_lp  = `BSG_SAFE_CLOG2(assoc_p)
    , localparam block_offset_width_lp = (bank_offset_width_lp + byte_offset_width_lp)
    , localparam index_width_lp = `BSG_SAFE_CLOG2(sets_p)
    , localparam way_width_lp = `BSG_SAFE_CLOG2(assoc_p)
    , localparam block_size_in_fill_lp = block_width_p / fill_width_p
    , localparam fill_size_in_bank_lp = fill_width_p / bank_width_lp
    , localparam fill_cnt_width_lp = `BSG_SAFE_CLOG2(block_size_in_fill_lp)
    , localparam bank_sub_offset_width_lp = `BSG_SAFE_CLOG2(fill_size_in_bank_lp)

    , localparam cache_req_width_lp = `bp_cache_req_width(dword_width_p, paddr_width_p)
    , localparam cache_req_metadata_width_lp = `bp_cache_req_metadata_width(assoc_p)
    , localparam cache_tag_mem_pkt_width_lp = `bp_cache_tag_mem_pkt_width(sets_p, assoc_p, ptag_width_p)
    , localparam cache_data_mem_pkt_width_lp = `bp_cache_data_mem_pkt_width(sets_p, assoc_p, block_width_p, fill_width_p)
    , localparam cache_stat_mem_pkt_width_lp = `bp_cache_stat_mem_pkt_width(sets_p, assoc_p)

    // Fill size parameterisations -
    , localparam bp_mem_msg_size_e block_msg_size_lp = (fill_width_p == 512)
                                                      ? e_mem_msg_size_64
                                                      : (fill_width_p == 256)
                                                        ? e_mem_msg_size_32
                                                        : (fill_width_p == 128)
                                                          ? e_mem_msg_size_16
                                                          : (fill_width_p == 64)
                                                            ? e_mem_msg_size_8
                                                            : e_mem_msg_size_64
    )
   (input                                            clk_i
    , input                                          reset_i

    , input [lce_id_width_p-1:0]                     lce_id_i

    , input [cache_req_width_lp-1:0]                 cache_req_i
    , input                                          cache_req_v_i
    , output logic                                   cache_req_ready_o
    , input [cache_req_metadata_width_lp-1:0]        cache_req_metadata_i
    , input                                          cache_req_metadata_v_i
    , output logic                                   cache_req_complete_o
    , output logic                                   cache_req_critical_o

    , output logic [cache_tag_mem_pkt_width_lp-1:0]  tag_mem_pkt_o
    , output logic                                   tag_mem_pkt_v_o
    , input                                          tag_mem_pkt_yumi_i
    , input [ptag_width_p-1:0]                       tag_mem_i

    , output logic [cache_data_mem_pkt_width_lp-1:0] data_mem_pkt_o
    , output logic                                   data_mem_pkt_v_o
    , input                                          data_mem_pkt_yumi_i
    , input [block_width_p-1:0]                      data_mem_i

    , output logic [cache_stat_mem_pkt_width_lp-1:0] stat_mem_pkt_o
    , output logic                                   stat_mem_pkt_v_o
    , input                                          stat_mem_pkt_yumi_i
    , input [stat_info_width_lp-1:0]                 stat_mem_i

    , output logic                                   credits_full_o
    , output logic                                   credits_empty_o

    , output [cce_mem_msg_width_lp-1:0]              mem_cmd_o
    , output logic                                   mem_cmd_v_o
    , input                                          mem_cmd_ready_i

    , input [cce_mem_msg_width_lp-1:0]               mem_resp_i
    , input                                          mem_resp_v_i
    , output logic                                   mem_resp_yumi_o
    );

  `declare_bp_me_if(paddr_width_p, cce_block_width_p, lce_id_width_p, lce_assoc_p);
  `declare_bp_cache_service_if(paddr_width_p, ptag_width_p, sets_p, assoc_p, dword_width_p, block_width_p, fill_width_p, cache);
  `declare_bp_cache_stat_info_s(assoc_p, cache);

  `bp_cast_i(bp_cache_req_s, cache_req);
  `bp_cast_o(bp_cache_tag_mem_pkt_s, tag_mem_pkt);
  `bp_cast_o(bp_cache_data_mem_pkt_s, data_mem_pkt);
  `bp_cast_o(bp_cache_stat_mem_pkt_s, stat_mem_pkt);

  `bp_cast_o(bp_cce_mem_msg_s, mem_cmd);
  `bp_cast_i(bp_cce_mem_msg_s, mem_resp);

  logic cache_req_v_r, dirty_data_v_r, dirty_tag_v_r, dirty_stat_v_r;
  always_ff @(posedge clk_i)
    begin
      cache_req_v_r <= cache_req_v_i;
      dirty_data_v_r <= data_mem_pkt_yumi_i & (data_mem_pkt_cast_o.opcode == e_cache_data_mem_read);
      dirty_tag_v_r <= tag_mem_pkt_yumi_i & (tag_mem_pkt_cast_o.opcode == e_cache_tag_mem_read);
      dirty_stat_v_r <= stat_mem_pkt_yumi_i & (stat_mem_pkt_cast_o.opcode == e_cache_stat_mem_read);
    end

  bp_cache_req_s cache_req_r;
  bsg_dff_reset_en
   #(.width_p($bits(bp_cache_req_s)))
   cache_req_reg
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.en_i(cache_req_v_i)
     ,.data_i(cache_req_cast_i)
     ,.data_o(cache_req_r)
     );

  bp_cache_req_metadata_s cache_req_metadata_r;
  bsg_dff_en_bypass
   #(.width_p($bits(bp_cache_req_metadata_s)))
   metadata_reg
    (.clk_i(clk_i)

     ,.en_i(cache_req_metadata_v_i)
     ,.data_i(cache_req_metadata_i)
     ,.data_o(cache_req_metadata_r)
     );

  logic cache_req_metadata_v_r;
  bsg_dff_en_bypass
   #(.width_p(1))
   metadata_v_reg
    (.clk_i(clk_i)

     ,.en_i(cache_req_v_i | cache_req_metadata_v_i)
     ,.data_i(cache_req_metadata_v_i)
     ,.data_o(cache_req_metadata_v_r)
     );

  logic [block_width_p-1:0] dirty_data_r;
  bsg_dff_en_bypass
   #(.width_p(block_width_p))
   dirty_data_reg
    (.clk_i(clk_i)

    ,.en_i(dirty_data_v_r)
    ,.data_i(data_mem_i)
    ,.data_o(dirty_data_r)
    );

  logic [ptag_width_p-1:0] dirty_tag_r;
  bsg_dff_en_bypass
   #(.width_p(ptag_width_p))
   dirty_tag_reg
    (.clk_i(clk_i)

    ,.en_i(dirty_tag_v_r)
    ,.data_i(tag_mem_i)
    ,.data_o(dirty_tag_r)
    );

  bp_cache_stat_info_s dirty_stat_r;
  bsg_dff_en_bypass
   #(.width_p($bits(bp_cache_stat_info_s)))
   dirty_stat_reg
    (.clk_i(clk_i)

     ,.en_i(dirty_stat_v_r)
     ,.data_i(stat_mem_i)
     ,.data_o(dirty_stat_r)
     );

  // We can do a little better by sending the read_request before the writeback
  enum logic [3:0] {e_reset, e_clear, e_flush_read, e_flush_scan, e_flush_write, e_flush_fence, e_ready, e_send_critical, e_writeback_evict, e_writeback_read_req, e_writeback_write_req, e_write_wait, e_read_req, e_uc_read_wait} state_n, state_r;
  wire is_reset         = (state_r == e_reset);
  wire is_clear         = (state_r == e_clear);
  wire is_flush_read    = (state_r == e_flush_read);
  wire is_flush_scan    = (state_r == e_flush_scan);
  wire is_flush_write   = (state_r == e_flush_write);
  wire is_flush_fence   = (state_r == e_flush_fence);
  wire is_ready         = (state_r == e_ready);
  wire is_send_critical = (state_r == e_send_critical);
  wire is_writeback_evict = (state_r == e_writeback_evict); // read dirty data from cache to UCE
  wire is_writeback_read = (state_r == e_writeback_read_req); // read data from L2 to cache
  wire is_writeback_wb   = (state_r == e_writeback_write_req); // send dirty data from UCE to L2
  wire is_write_request  = (state_r == e_write_wait);
  wire is_read_request   = (state_r == e_read_req);

  // We check for uncached stores ealier than other requests, because they get sent out in ready
  wire flush_v_li         = cache_req_v_i & cache_req_cast_i.msg_type inside {e_cache_flush};
  wire clear_v_li         = cache_req_v_i & cache_req_cast_i.msg_type inside {e_cache_clear};
  wire uc_store_v_li      = cache_req_v_i & cache_req_cast_i.msg_type inside {e_uc_store};

  wire wt_store_v_li      = cache_req_v_i & cache_req_cast_i.msg_type inside {e_wt_store};

  wire store_resp_v_li    = mem_resp_v_i & mem_resp_cast_i.header.msg_type inside {e_cce_mem_wr, e_cce_mem_uc_wr};
  wire load_resp_v_li     = mem_resp_v_i & mem_resp_cast_i.header.msg_type inside {e_cce_mem_rd, e_cce_mem_uc_rd};

  wire miss_load_v_li  = cache_req_v_r & cache_req_r.msg_type inside {e_miss_load};
  wire miss_store_v_li = cache_req_v_r & cache_req_r.msg_type inside {e_miss_store};
  wire miss_v_li       = miss_load_v_li | miss_store_v_li;
  wire uc_load_v_li    = cache_req_v_r & cache_req_r.msg_type inside {e_uc_load};

  // When fill_width_p < block_width_p, multicycle fill and writeback is implemented in cache flush write,
  // cache miss load with and without dirty data writeback.
  // To track the progress of these multicycle opeation, two counters, fill_cnt and mem_cmd_cnt are added
  // In addition, mem_cmd_cnt is used to generated the addr in mem_cmd_o to request data from L2 and
  // to write back dirty data to L2 in the size of fill_width.
  logic [fill_cnt_width_lp-1:0] mem_cmd_cnt;
  logic [block_size_in_fill_lp-1:0] fill_index_shift;
  logic [bank_offset_width_lp-1:0] bank_index;
  if (fill_size_in_bank_lp == 1)
    begin
      assign bank_index =  mem_cmd_cnt;
      assign fill_index_shift = mem_resp_cast_i.header.addr[byte_offset_width_lp+:bank_offset_width_lp];
    end
  else
    begin
      assign bank_index = mem_cmd_cnt << bank_sub_offset_width_lp;
      assign fill_index_shift = mem_resp_cast_i.header.addr[byte_offset_width_lp+:bank_offset_width_lp] >> bank_sub_offset_width_lp;
    end

  logic fill_up, fill_done, mem_cmd_up, mem_cmd_done;
  if (fill_width_p == block_width_p)
    begin
      assign mem_cmd_cnt = 1'b0;
      assign fill_done = 1'b1;
      assign mem_cmd_done = 1'b1;
    end
  else
    begin
      logic [fill_cnt_width_lp-1:0] fill_cnt;
      bsg_counter_clear_up
       #(.max_val_p(block_size_in_fill_lp-1)
        ,.init_val_p(0)
        ,.disable_overflow_warning_p(1))
      fill_counter
        (.clk_i(clk_i)
        ,.reset_i(reset_i)

        ,.clear_i('0)
        ,.up_i(fill_up)

        ,.count_o(fill_cnt)
        );
      assign fill_done = (fill_cnt == block_size_in_fill_lp-1);

      bsg_counter_clear_up
       #(.max_val_p(block_size_in_fill_lp-1)
        ,.init_val_p(0)
        ,.disable_overflow_warning_p(1))
       mem_cmd_counter
        (.clk_i(clk_i)
        ,.reset_i(reset_i)

        ,.clear_i('0)
        ,.up_i(mem_cmd_up)

        ,.count_o(mem_cmd_cnt)
        );
      assign mem_cmd_done = (mem_cmd_cnt == block_size_in_fill_lp-1);
    end

  logic [index_width_lp-1:0] index_cnt;
  logic index_up;
  bsg_counter_clear_up
   #(.max_val_p(sets_p-1)
    ,.init_val_p(0)
    ,.disable_overflow_warning_p(1))
   index_counter
    (.clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.clear_i('0)
    ,.up_i(index_up)

    ,.count_o(index_cnt)
    );
  wire index_done = (index_cnt == sets_p-1);

  logic [way_width_lp-1:0] way_cnt;
  logic way_up;
  bsg_counter_clear_up
   #(.max_val_p(assoc_p-1)
    ,.init_val_p(0)
    ,.disable_overflow_warning_p(1))
   way_counter
    (.clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.clear_i('0)
    ,.up_i(way_up)

    ,.count_o(way_cnt)
    );
  wire way_done = (way_cnt == assoc_p-1);

  logic mem_cmd_done_r;
  bsg_dff_reset_set_clear
   #(.width_p(1)
    ,.clear_over_set_p(1)) // if 1, clear overrides set.
   mem_cmd_done_reg
    (.clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.set_i(mem_cmd_done & mem_cmd_v_o)
    ,.clear_i(cache_req_complete_o | way_up)
    ,.data_o(mem_cmd_done_r)
    );

  // Outstanding Requests Counter - counts all requests, cached and uncached
  //
  logic [`BSG_WIDTH(coh_noc_max_credits_p)-1:0] credit_count_lo;
  wire credit_v_li = mem_cmd_v_o;
  wire credit_ready_li = mem_cmd_ready_i;
  // credit is returned when request completes
  // UC store done for UC Store, UC Data for UC Load, Set Tag Wakeup for
  // a miss that is actually an upgrade, and data and tag for normal requests.
  wire credit_returned_li = mem_resp_yumi_o;
  bsg_flow_counter
   #(.els_p(coh_noc_max_credits_p))
   credit_counter
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.v_i(credit_v_li)
     ,.ready_i(credit_ready_li)

     ,.yumi_i(credit_returned_li)
     ,.count_o(credit_count_lo)
     );
  assign credits_full_o = (credit_count_lo == coh_noc_max_credits_p);
  assign credits_empty_o = (credit_count_lo == 0);

  logic [fill_width_p-1:0] writeback_data;
  bsg_mux
   #(.width_p(fill_width_p)
    ,.els_p(block_size_in_fill_lp))
   writeback_mux
    (.data_i(dirty_data_r)
    ,.sel_i(mem_cmd_cnt)
    ,.data_o(writeback_data)
    );

  // We ack mem_resps for uncached stores no matter what, so mem_resp_yumi_lo is for other responses
  logic mem_resp_yumi_lo;
  assign mem_resp_yumi_o = mem_resp_yumi_lo | store_resp_v_li;
  always_comb
    begin
      cache_req_ready_o = '0;

      index_up = '0;
      way_up   = '0;
      fill_up  = '0;
      mem_cmd_up = '0;

      tag_mem_pkt_cast_o  = '0;
      tag_mem_pkt_v_o     = '0;
      data_mem_pkt_cast_o = '0;
      data_mem_pkt_v_o    = '0;
      stat_mem_pkt_cast_o = '0;
      stat_mem_pkt_v_o    = '0;

      cache_req_complete_o = '0;
      cache_req_critical_o = '0;

      mem_cmd_cast_o   = '0;
      mem_cmd_v_o      = '0;
      mem_resp_yumi_lo = '0;

      state_n = state_r;

      unique case (state_r)
        e_reset:
          begin
            state_n = e_clear;
          end
        e_clear:
          begin
            tag_mem_pkt_cast_o.opcode = e_cache_tag_mem_set_clear;
            tag_mem_pkt_cast_o.index  = index_cnt;
            tag_mem_pkt_v_o = 1'b1;

            stat_mem_pkt_cast_o.opcode = e_cache_stat_mem_set_clear;
            stat_mem_pkt_cast_o.index  = index_cnt;
            stat_mem_pkt_v_o = 1'b1;

            index_up = tag_mem_pkt_yumi_i & stat_mem_pkt_yumi_i;

            cache_req_complete_o = (index_done & index_up);

            state_n = (index_done & index_up) ? e_ready : e_clear;
          end
        e_flush_read:
          begin
            stat_mem_pkt_cast_o.opcode = e_cache_stat_mem_read;
            stat_mem_pkt_cast_o.index = index_cnt;
            stat_mem_pkt_v_o = 1'b1;

            state_n = stat_mem_pkt_yumi_i ? e_flush_scan : e_flush_read;
          end
        e_flush_scan:
          begin
            // Could check if |dirty_stat_r to skip index entirely
            if (dirty_stat_r[way_cnt])
              begin
                data_mem_pkt_cast_o.opcode = e_cache_data_mem_read;
                data_mem_pkt_cast_o.index  = index_cnt;
                data_mem_pkt_cast_o.way_id = way_cnt;
                data_mem_pkt_v_o = 1'b1;
                data_mem_pkt_cast_o.fill_index = {block_size_in_fill_lp{1'b1}};

                tag_mem_pkt_cast_o.opcode = e_cache_tag_mem_read;
                tag_mem_pkt_cast_o.index  = index_cnt;
                tag_mem_pkt_cast_o.way_id = way_cnt;
                tag_mem_pkt_v_o = 1'b1;

                stat_mem_pkt_cast_o.opcode = e_cache_stat_mem_clear_dirty;
                stat_mem_pkt_cast_o.index  = index_cnt;
                stat_mem_pkt_cast_o.way_id = way_cnt;
                stat_mem_pkt_v_o = 1'b1;

                state_n = (data_mem_pkt_yumi_i & tag_mem_pkt_yumi_i & stat_mem_pkt_yumi_i) ? e_flush_write : e_flush_scan;
              end
            else
              begin
                way_up   = 1'b1;
                index_up = way_done;

                state_n = (index_done & way_done)
                          ? e_flush_fence
                          : way_done
                            ? e_flush_read
                            : e_flush_scan;
              end
          end
        e_flush_write:
          begin
            mem_cmd_cast_o.header.msg_type = e_cce_mem_wr;
            mem_cmd_cast_o.header.addr     = {dirty_tag_r, index_cnt, bank_index, byte_offset_width_lp'(0)};
            mem_cmd_cast_o.header.size     = block_msg_size_lp;
            mem_cmd_cast_o.header.payload.lce_id = lce_id_i;
            mem_cmd_cast_o.data                  = writeback_data;
            mem_cmd_v_o = mem_cmd_ready_i;
            mem_cmd_up = mem_cmd_v_o;

            way_up = mem_cmd_done & mem_cmd_v_o;
            index_up = way_done & mem_cmd_done & mem_cmd_v_o;

            state_n = (mem_cmd_done & mem_cmd_v_o & index_done & way_done)
                      ? e_flush_fence
                      : index_up
                        ? e_flush_read
                        : way_up
                          ? e_flush_scan
                          : e_flush_write;
          end
        e_flush_fence:
          begin
            cache_req_complete_o = credits_empty_o;

            state_n = cache_req_complete_o ? e_ready : e_flush_fence;
          end
        e_ready:
          begin
            cache_req_ready_o = mem_cmd_ready_i & ~credits_full_o;
            if (uc_store_v_li)
              begin
                mem_cmd_cast_o.header.msg_type       = e_cce_mem_uc_wr;
                mem_cmd_cast_o.header.addr           = cache_req_cast_i.addr;
                mem_cmd_cast_o.header.size           = bp_mem_msg_size_e'(cache_req_cast_i.size);
                mem_cmd_cast_o.header.payload.lce_id = lce_id_i;
                mem_cmd_cast_o.data                  = cache_req_cast_i.data;
                mem_cmd_v_o = mem_cmd_ready_i;
              end
            else if (wt_store_v_li)
              begin
                mem_cmd_cast_o.header.msg_type       = e_cce_mem_wr;
                mem_cmd_cast_o.header.addr           = cache_req_cast_i.addr;
                mem_cmd_cast_o.header.size           = bp_mem_msg_size_e'(cache_req_cast_i.size);
                mem_cmd_cast_o.header.payload.lce_id = lce_id_i;
                mem_cmd_cast_o.data                  = cache_req_cast_i.data;
                mem_cmd_v_o = mem_cmd_ready_i;
              end
            else
              begin
                state_n = cache_req_v_i
                          ? flush_v_li
                            ? e_flush_read
                            : clear_v_li
                              ? e_clear
                              : e_send_critical
                          : e_ready;
              end
          end
        e_send_critical:
          if (miss_v_li)
            begin
              mem_cmd_cast_o.header.msg_type       = e_cce_mem_rd;
              mem_cmd_cast_o.header.addr           = {cache_req_r.addr[paddr_width_p-1:block_offset_width_lp], block_offset_width_lp'(0)};
              mem_cmd_cast_o.header.size           = block_msg_size_lp;
              mem_cmd_cast_o.header.payload.way_id = lce_assoc_p'(cache_req_metadata_r.repl_way);
              mem_cmd_cast_o.header.payload.lce_id = lce_id_i;
              mem_cmd_v_o = mem_cmd_ready_i;
              mem_cmd_up = mem_cmd_v_o;
              state_n = mem_cmd_v_o
                        ? cache_req_metadata_r.dirty
                          ? e_writeback_evict
                          : e_read_req
                        : e_send_critical;
            end
          else if (uc_load_v_li)
            begin
              mem_cmd_cast_o.header.msg_type       = e_cce_mem_uc_rd;
              mem_cmd_cast_o.header.addr           = cache_req_r.addr;
              mem_cmd_cast_o.header.size           = e_mem_msg_size_8;
              mem_cmd_cast_o.header.payload.lce_id = lce_id_i;
              mem_cmd_v_o = mem_cmd_ready_i;

              state_n = mem_cmd_v_o ? e_uc_read_wait : e_send_critical;
            end
        e_writeback_evict:
          begin
            data_mem_pkt_cast_o.opcode = e_cache_data_mem_read;
            data_mem_pkt_cast_o.index  = cache_req_r.addr[block_offset_width_lp+:index_width_lp];
            data_mem_pkt_cast_o.way_id = cache_req_metadata_r.repl_way;
            data_mem_pkt_cast_o.fill_index = {block_size_in_fill_lp{1'b1}};
            data_mem_pkt_v_o = 1'b1;

            tag_mem_pkt_cast_o.opcode  = e_cache_tag_mem_read;
            tag_mem_pkt_cast_o.index   = cache_req_r.addr[block_offset_width_lp+:index_width_lp];
            tag_mem_pkt_cast_o.way_id  = cache_req_metadata_r.repl_way;
            tag_mem_pkt_v_o = 1'b1;

            stat_mem_pkt_cast_o.opcode = e_cache_stat_mem_clear_dirty;
            stat_mem_pkt_cast_o.index  = cache_req_r.addr[block_offset_width_lp+:index_width_lp];
            stat_mem_pkt_cast_o.way_id = cache_req_metadata_r.repl_way;
            stat_mem_pkt_v_o = 1'b1;

            state_n = (data_mem_pkt_yumi_i & tag_mem_pkt_yumi_i & stat_mem_pkt_yumi_i) ? e_writeback_read_req : e_writeback_evict;
          end
        e_writeback_read_req:
          begin
            // send the sub-block from L2 to cache
            tag_mem_pkt_cast_o.opcode = e_cache_tag_mem_set_tag;
            tag_mem_pkt_cast_o.index  = mem_resp_cast_i.header.addr[block_offset_width_lp+:index_width_lp];
            // We fill in M because we don't want to trigger additional coherence traffic
            tag_mem_pkt_cast_o.way_id = mem_resp_cast_i.header.payload.way_id[0+:`BSG_SAFE_CLOG2(assoc_p)];
            tag_mem_pkt_cast_o.state  = e_COH_M;
            tag_mem_pkt_cast_o.tag    = mem_resp_cast_i.header.addr[block_offset_width_lp+index_width_lp+:ptag_width_p];
            tag_mem_pkt_v_o = load_resp_v_li;

            data_mem_pkt_cast_o.opcode = e_cache_data_mem_write;
            data_mem_pkt_cast_o.index  = mem_resp_cast_i.header.addr[block_offset_width_lp+:index_width_lp];
            data_mem_pkt_cast_o.way_id = mem_resp_cast_i.header.payload.way_id[0+:`BSG_SAFE_CLOG2(assoc_p)];
            data_mem_pkt_cast_o.data   = mem_resp_cast_i.data;
            data_mem_pkt_cast_o.fill_index = 1'b1 << fill_index_shift;
            data_mem_pkt_v_o = load_resp_v_li;

            cache_req_critical_o = '0;
            fill_up = tag_mem_pkt_yumi_i & data_mem_pkt_yumi_i;
            mem_resp_yumi_lo = tag_mem_pkt_yumi_i & data_mem_pkt_yumi_i;
            // request next sub-block
            mem_cmd_cast_o.header.msg_type       = e_cce_mem_rd;
            mem_cmd_cast_o.header.addr           = {cache_req_r.addr[paddr_width_p-1:block_offset_width_lp], bank_index, byte_offset_width_lp'(0)};
            mem_cmd_cast_o.header.size           = block_msg_size_lp;
            mem_cmd_cast_o.header.payload.way_id = lce_assoc_p'(cache_req_metadata_r.repl_way);
            mem_cmd_cast_o.header.payload.lce_id = lce_id_i;
            mem_cmd_v_o = mem_cmd_ready_i & ~mem_cmd_done_r;
            mem_cmd_up = mem_cmd_v_o;

            state_n = (fill_done & mem_cmd_done_r & tag_mem_pkt_yumi_i & data_mem_pkt_yumi_i) ? e_writeback_write_req : e_writeback_read_req;
          end
        e_writeback_write_req:
          begin
            mem_cmd_cast_o.header.msg_type = e_cce_mem_wr;
            mem_cmd_cast_o.header.addr     = {dirty_tag_r, cache_req_r.addr[block_offset_width_lp+:index_width_lp], bank_index, byte_offset_width_lp'(0)};
            mem_cmd_cast_o.header.size     = block_msg_size_lp;
            mem_cmd_cast_o.header.payload.lce_id = lce_id_i;
            mem_cmd_cast_o.data                  = writeback_data;
            mem_cmd_v_o = mem_cmd_ready_i;
            mem_cmd_up = mem_cmd_v_o;

            cache_req_complete_o = mem_cmd_done & mem_cmd_v_o;
            state_n = cache_req_complete_o ? e_ready : e_writeback_write_req;
          end
        e_read_req:
          begin
            // send the sub-block from L2 to cache
            tag_mem_pkt_cast_o.opcode = e_cache_tag_mem_set_tag;
            tag_mem_pkt_cast_o.index  = mem_resp_cast_i.header.addr[block_offset_width_lp+:index_width_lp];
            // We fill in M because we don't want to trigger additional coherence traffic
            tag_mem_pkt_cast_o.way_id = mem_resp_cast_i.header.payload.way_id[0+:`BSG_SAFE_CLOG2(assoc_p)];
            tag_mem_pkt_cast_o.state  = e_COH_M;
            tag_mem_pkt_cast_o.tag    = mem_resp_cast_i.header.addr[block_offset_width_lp+index_width_lp+:ptag_width_p];
            tag_mem_pkt_v_o = load_resp_v_li;

            data_mem_pkt_cast_o.opcode = e_cache_data_mem_write;
            data_mem_pkt_cast_o.index  = mem_resp_cast_i.header.addr[block_offset_width_lp+:index_width_lp];
            data_mem_pkt_cast_o.way_id = mem_resp_cast_i.header.payload.way_id[0+:`BSG_SAFE_CLOG2(assoc_p)];
            data_mem_pkt_cast_o.data   = mem_resp_cast_i.data;
            data_mem_pkt_cast_o.fill_index = 1'b1 << fill_index_shift;
            data_mem_pkt_v_o = load_resp_v_li;

            cache_req_critical_o = '0;
            fill_up = tag_mem_pkt_yumi_i & data_mem_pkt_yumi_i;
            mem_resp_yumi_lo = tag_mem_pkt_yumi_i & data_mem_pkt_yumi_i;
            // request next sub-block
            mem_cmd_cast_o.header.msg_type       = e_cce_mem_rd;
            mem_cmd_cast_o.header.addr           = {cache_req_r.addr[paddr_width_p-1:block_offset_width_lp], bank_index, byte_offset_width_lp'(0)};
            mem_cmd_cast_o.header.size           = block_msg_size_lp;
            mem_cmd_cast_o.header.payload.way_id = lce_assoc_p'(cache_req_metadata_r.repl_way);
            mem_cmd_cast_o.header.payload.lce_id = lce_id_i;
            mem_cmd_v_o = mem_cmd_ready_i & ~mem_cmd_done_r;
            mem_cmd_up = mem_cmd_v_o;

            cache_req_complete_o = fill_done & mem_cmd_done_r & tag_mem_pkt_yumi_i & data_mem_pkt_yumi_i;
            state_n = cache_req_complete_o ? e_ready : e_read_req;
          end
        e_uc_read_wait:
          begin
            data_mem_pkt_cast_o.opcode = e_cache_data_mem_uncached;
            data_mem_pkt_cast_o.data = mem_resp_cast_i.data;
            data_mem_pkt_v_o = load_resp_v_li;

            cache_req_complete_o = data_mem_pkt_yumi_i;
            mem_resp_yumi_lo = cache_req_complete_o;

            state_n = cache_req_complete_o ? e_ready : e_uc_read_wait;
          end
        default: state_n = e_reset;
      endcase
    end

  // synopsys sync_set_reset "reset_i"
  always_ff @(posedge clk_i)
    if (reset_i)
      state_r <= e_reset;
    else
      state_r <= state_n;

////synopsys translate_on
//always_ff @(negedge clk_i)
//  begin
//    assert (reset_i || ~wt_store_v_li)
//      $display("Unsupported op: wt store %p", cache_req_cast_i);
//  end
////synopsys translate_off

endmodule
