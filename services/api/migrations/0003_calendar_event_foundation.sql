CREATE INDEX idx_calendar_members_user_id ON calendar_members(user_id);

CREATE INDEX idx_events_calendar_id_starts_at ON events(calendar_id, starts_at);

ALTER TABLE calendar_members
    ADD CONSTRAINT calendar_members_role_check
    CHECK (role IN ('owner', 'editor', 'viewer'));

ALTER TABLE events
    ADD CONSTRAINT events_time_range_check
    CHECK (ends_at >= starts_at);
