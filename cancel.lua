-- Cancel(0, jid)
-- --------------
-- Cancel a job from taking place. It will be deleted from the system, and any
-- attempts to renew a heartbeat will fail, and any attempts to complete it
-- will fail. If you try to get the data on the object, you will get nothing.
--
-- Args:
--    1) jid

if #KEYS > 0 then error('Cancel(): No Keys should be provided') end

local jid    = assert(ARGV[1], 'Cancel(): Arg "jid" missing.')

-- Find any stage it's associated with and remove its from that stage
local state, queue, failure, worker = unpack(redis.call('hmget', 'ql:j:' .. jid, 'state', 'queue', 'failure', 'worker'))

if state == 'complete' then
	return False
else
	-- If this job has dependents, then we should probably fail
	if redis.call('zcard', 'ql:j:' .. jid .. '-dependents') > 0 then
		error('Cancel(): ' .. jid .. ' has un-canceled jobs that depend on it')
	end
	
	-- Remove this job from whatever worker has it, if any
	if worker then
		redis.call('zrem', 'ql:w:' .. worker .. ':jobs', jid)
	end
	
	-- Remove it from that queue
	if queue then
		redis.call('zrem', 'ql:q:' .. queue .. '-work', jid)
		redis.call('zrem', 'ql:q:' .. queue .. '-locks', jid)
		redis.call('zrem', 'ql:q:' .. queue .. '-scheduled', jid)
		redis.call('zrem', 'ql:q:' .. queue .. '-depends', jid)
	end
	
	-- Delete any notion of dependencies it has
	redis.call('del', 'ql:j:' .. jid .. '-dependencies')
	
	-- If we're in the failed state, remove all of our data
	if state == 'failed' then
		failure = cjson.decode(failure)
		-- We need to make this remove it from the failed queues
		redis.call('lrem', 'ql:f:' .. failure.group, 0, jid)
		if redis.call('llen', 'ql:f:' .. failure.group) == 0 then
			redis.call('srem', 'ql:failures', failure.group)
		end
	end
	
	-- Just go ahead and delete our data
	redis.call('del', 'ql:j:' .. jid)
end
