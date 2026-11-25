-- People in an "add person" call (a 1:1 call that grew into a small group call, no group needed).
CREATE TABLE adhoc_call_members (
  call_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  PRIMARY KEY (call_id, user_id)
);
