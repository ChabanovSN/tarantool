test_run = require('test_run').new()

fiber = require('fiber')
net_box = require('net.box')

box.schema.user.grant('guest', 'read,write,execute', 'universe')
conn = net_box.connect(box.cfg.listen)
conn2 = net_box.connect(box.cfg.listen)
active = 0
finished = 0
continue = false
limit = box.cfg.iproto_msg_max
run_max = (limit - 100) / 2

old_readahead = box.cfg.readahead
box.cfg{readahead = 9000}
long_str = string.rep('a', 1000)

test_run:cmd("setopt delimiter ';'")
function do_long_f(...)
	active = active + 1
	while not continue do
		fiber.sleep(0.1)
	end
	active = active - 1
	finished = finished + 1
end;

function do_long(c)
	c:call('do_long_f', {long_str})
end;

function run_workers(c)
	finished = 0
	continue = false
	for i = 1, run_max do
		fiber.create(do_long, c)
	end
end;

-- Wait until 'active' stops growing - it means, that the input
-- is blocked.
function wait_block()
	local old_val = -1
	while old_val ~= active do
		old_val = active
		fiber.sleep(0.1)
	end
end;

function wait_finished(needed)
	continue = true
	while finished ~= needed do fiber.sleep(0.01) end
end;
test_run:cmd("setopt delimiter ''");

--
-- Test that message count limit is reachable.
--
run_workers(conn)
run_workers(conn2)
wait_block()
active == run_max * 2 or active
wait_finished(active)

--
-- Test that each message in a batch is checked. When a limit is
-- reached, other messages must be processed later.
--
run_max = limit * 5
run_workers(conn)
wait_block()
active
wait_finished(run_max)

--
-- gh-3320: allow to change maximal count of messages.
--

--
-- Test minimal iproto msg count.
--
box.cfg{iproto_msg_max = 2}
conn:ping()
#conn.space._space:select{} > 0
run_max = 15
run_workers(conn)
wait_block()
active
wait_finished(run_max)

--
-- Increate maximal message count when nothing is blocked.
--
box.cfg{iproto_msg_max = limit * 2}
run_max = limit * 2 - 100
run_workers(conn)
wait_block()
active == run_max
-- Max can be decreased back even if now the limit is violated.
-- But a new input is blocked in such a case.
box.cfg{iproto_msg_max = limit}
old_active = active
for i = 1, 300 do fiber.create(do_long, conn) end
-- Afer time active count is not changed - the input is blocked.
wait_block()
active == old_active
wait_finished(active + 300)

--
-- Check that changing iproto_msg_max can resume stopped
-- connections.
--
run_max = limit / 2 + 100
run_workers(conn)
run_workers(conn2)
wait_block()
active >= limit
active < run_max * 2
box.cfg{iproto_msg_max = limit * 2}
wait_block()
active == run_max * 2
wait_finished(active)

--
-- Test TX fiber pool size limit. It is increased together with
-- iproto msg max.
--
run_max = 2500
box.cfg{iproto_msg_max = 5000}
run_workers(conn)
run_workers(conn2)
wait_block()
active
wait_finished(run_max * 2)

conn2:close()
conn:close()

box.schema.user.revoke('guest', 'read,write,execute', 'universe')
box.cfg{readahead = old_readahead, iproto_msg_max = limit}
