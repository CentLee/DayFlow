ALTER TABLE calendars
    ADD COLUMN kind TEXT NOT NULL DEFAULT 'shared';

ALTER TABLE calendars
    ADD CONSTRAINT calendars_kind_check
    CHECK (kind IN ('personal', 'shared'));

ALTER TABLE calendar_invites
    ADD COLUMN delivery_channel TEXT NOT NULL DEFAULT 'email';

ALTER TABLE calendar_invites
    ADD CONSTRAINT calendar_invites_delivery_channel_check
    CHECK (delivery_channel IN ('email', 'sms'));
