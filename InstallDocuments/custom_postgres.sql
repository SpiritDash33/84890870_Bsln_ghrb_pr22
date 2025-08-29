-- File Name: db/custom_postgres.sql
-- Created Date: 2025-08-28
-- Modified Date: 2025-08-28
-- Version: 1.0.0
-- Description: PostgreSQL custom features for Job Ticket System, including extension, view, functions, triggers, indexes, and initial data.
-- Comments:
-- - Loaded via Django migration RunSQL.
-- - Assumes tables are created by Django models.
-- Update Notes:
-- - 2025-08-28 (v1.0.0): Extracted from original schema for separate handling.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE VIEW daily_alert_counts AS
SELECT user_id, created_at::date AS alert_date, COUNT(*) AS alert_count
FROM alerts
WHERE severity != 'critical'
GROUP BY user_id, alert_date;

CREATE OR REPLACE FUNCTION check_failed_logins() RETURNS TRIGGER AS $$
DECLARE
    failed_count INTEGER;
BEGIN
    IF NEW.success = FALSE THEN
        SELECT COUNT(*) INTO failed_count
        FROM login_attempts
        WHERE ip_address = NEW.ip_address AND success = FALSE
        AND attempt_time > CURRENT_TIMESTAMP - INTERVAL '1 hour';
        IF failed_count > 5 THEN
            INSERT INTO alerts (user_id, alert_type, severity, message, created_at)
            VALUES (NEW.user_id, 'security', 'high', 'Multiple failed login attempts from IP: ' || NEW.ip_address, CURRENT_TIMESTAMP);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER failed_login_alert_trigger
AFTER INSERT ON login_attempts
FOR EACH ROW EXECUTE FUNCTION check_failed_logins();

CREATE OR REPLACE FUNCTION limit_daily_alerts() RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT COUNT(*) FROM alerts WHERE user_id = NEW.user_id AND created_at::date = CURRENT_DATE AND severity != 'critical') >= 5 THEN
        RAISE EXCEPTION 'Daily non-critical alert limit reached';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER daily_alert_limit_trigger
BEFORE INSERT ON alerts
FOR EACH ROW EXECUTE FUNCTION limit_daily_alerts();

CREATE OR REPLACE FUNCTION escalate_alerts() RETURNS VOID AS $$
BEGIN
    UPDATE alerts
    SET severity = CASE
        WHEN severity = 'low' THEN 'medium'
        WHEN severity = 'medium' THEN 'high'
        WHEN severity = 'high' THEN 'critical'
    END
    WHERE is_resolved = FALSE AND created_at < CURRENT_TIMESTAMP - INTERVAL '1 day';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_unauthorized_access() RETURNS TRIGGER AS $$
DECLARE
    user_role_admin BOOLEAN;
    user_role_manager BOOLEAN;
    is_authorized BOOLEAN;
BEGIN
    SELECT user_is_admin, user_is_manager INTO user_role_admin, user_role_manager
    FROM users WHERE user_id = NEW.user_id;

    is_authorized = FALSE;
    IF NEW.action = 'DELETE' THEN
        IF user_role_admin THEN
            is_authorized = TRUE;
        ELSIF user_role_manager AND NEW.table_name IN ('ticket_entries', 'ticket_misc_entries') THEN
            is_authorized = TRUE;
        END IF;
    ELSIF NEW.action = 'UPDATE' AND NEW.table_name IN ('users', 'tickets', 'ticket_entries', 'ticket_misc_entries') THEN
        IF user_role_admin OR (user_role_manager AND NEW.table_name IN ('ticket_entries', 'ticket_misc_entries')) THEN
            is_authorized = TRUE;
        ELSIF NEW.table_name IN ('ticket_entries', 'ticket_misc_entries') THEN
            IF EXISTS (
                SELECT 1 FROM ticket_entries WHERE id = NEW.record_id AND user_id = NEW.user_id
                UNION
                SELECT 1 FROM ticket_misc_entries WHERE id = NEW.record_id AND user_id = NEW.user_id
            ) THEN
                is_authorized = TRUE;
            END IF;
        END IF;
    END IF;

    IF NOT is_authorized THEN
        INSERT INTO alerts (user_id, alert_type, severity, message, created_at)
        VALUES (NEW.user_id, 'security', 'critical', 
                CONCAT('Unauthorized access attempt by user: ', NEW.user_id, ' on table: ', NEW.table_name, ', action: ', NEW.action), 
                CURRENT_TIMESTAMP);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER unauthorized_access_alert_trigger
AFTER INSERT ON history
FOR EACH ROW EXECUTE FUNCTION check_unauthorized_access();

CREATE OR REPLACE FUNCTION check_ticket_entry_alerts() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.job_materials_needed IS NOT NULL OR
       NEW.job_access_needed IS NOT NULL OR
       NEW.job_programming_changes IS NOT NULL OR
       NEW.job_followup_required = TRUE THEN
        INSERT INTO alerts (user_id, entry_id, alert_type, severity, message, created_at)
        VALUES (NEW.user_id, NEW.id, 'job-related', 'medium',
                CONCAT('Action required for job: ', NEW.job_name), CURRENT_TIMESTAMP);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ticket_entry_alert_trigger
AFTER INSERT OR UPDATE ON ticket_entries
FOR EACH ROW EXECUTE FUNCTION check_ticket_entry_alerts();

CREATE INDEX idx_users_oauth ON users (oauth_provider, oauth_id) WHERE oauth_id IS NOT NULL;
CREATE INDEX idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX idx_user_sessions_is_active ON user_sessions(is_active);
CREATE INDEX idx_login_attempts_email ON login_attempts(email);
CREATE INDEX idx_ticket_entries_user_id ON ticket_entries(user_id);
CREATE INDEX idx_ticket_entries_ticket_id ON ticket_entries(ticket_id);
CREATE INDEX idx_ticket_entries_job_start_date ON ticket_entries(job_start_date);
CREATE INDEX idx_ticket_misc_entries_user_id ON ticket_misc_entries(user_id);
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_group_id ON notifications(group_id);
CREATE INDEX idx_alerts_entry_id ON alerts(entry_id);
CREATE INDEX idx_alerts_user_id ON alerts(user_id);
CREATE INDEX idx_alerts_group_id ON alerts(group_id);
CREATE INDEX idx_alerts_alert_type ON alerts(alert_type);
CREATE INDEX idx_alerts_severity ON alerts(severity);
CREATE INDEX idx_alerts_unresolved ON alerts (alert_type, severity) WHERE is_resolved = FALSE;
CREATE INDEX idx_ticket_entry_devices_entry_id ON ticket_entry_devices(entry_id);
CREATE INDEX idx_ticket_entry_devices_device_id ON ticket_entry_devices(device_id);
CREATE INDEX idx_login_attempts_attempt_time ON login_attempts(attempt_time);
CREATE INDEX idx_login_attempts_email_ip ON login_attempts(email, ip_address);
CREATE INDEX idx_login_attempts_ip_time ON login_attempts(ip_address, attempt_time);

INSERT INTO groups (group_name) VALUES ('field'), ('manager'), ('admin');
