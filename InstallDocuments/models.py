from django.contrib.auth.models import AbstractUser
from django.db import models
import uuid

class User(AbstractUser):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    username = None
    first_name = None
    last_name = None
    email = models.EmailField(unique=True)
    password = models.CharField(max_length=255)
    is_staff = models.BooleanField(default=False)
    is_superuser = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    date_joined = models.DateTimeField(auto_now_add=True)
    last_login = models.DateTimeField(null=True, blank=True)
    user_name = models.CharField(max_length=255)
    user_alias = models.CharField(max_length=255, null=True, blank=True)
    user_preferred_color = models.CharField(max_length=50, null=True, blank=True)
    user_preferred_landing_page = models.CharField(max_length=255, null=True, blank=True)
    user_preferred_profile_picture = models.TextField(null=True, blank=True)
    user_preferred_light_or_dark_mode_mobile = models.CharField(max_length=10, default='dark')
    user_preferred_light_or_dark_mode_desktop = models.CharField(max_length=10, default='light')
    user_preferred_enable_alerts = models.JSONField(null=True, blank=True)
    user_preferred_enable_notifications = models.JSONField(null=True, blank=True)
    user_is_admin = models.BooleanField(default=False)
    user_is_manager = models.BooleanField(default=False)
    user_is_email_verified = models.BooleanField(default=False)
    user_preferred_timezone = models.CharField(max_length=50, default='America/Los_Angeles')
    user_preferred_display_mode = models.CharField(max_length=10, choices=[('desktop', 'desktop'), ('mobile', 'mobile')], null=True, blank=True)
    user_agreed_to_terms = models.BooleanField(default=False)
    oauth_provider = models.CharField(max_length=50, null=True, blank=True)
    oauth_id = models.CharField(max_length=255, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['user_name']

    class Meta:
        db_table = 'users'

    def save(self, *args, **kwargs):
        self.is_superuser = self.user_is_admin
        self.is_staff = self.user_is_manager or self.user_is_admin
        super().save(*args, **kwargs)

class EmailVerificationToken(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey('User', on_delete=models.CASCADE)
    token = models.CharField(max_length=255, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()

    class Meta:
        db_table = 'email_verification_tokens'

class UserSession(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey('User', on_delete=models.CASCADE)
    login_origin = models.CharField(max_length=255)
    token = models.CharField(max_length=512, unique=True)
    issued_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    last_accessed_at = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=False)
    device_info = models.CharField(max_length=255, null=True, blank=True)
    ip_address = models.CharField(max_length=45, null=True, blank=True)

    class Meta:
        db_table = 'user_sessions'

class LoginAttempt(models.Model):
    id = models.AutoField(primary_key=True)
    user = models.ForeignKey('User', null=True, blank=True, on_delete=models.SET_NULL)
    email = models.CharField(max_length=255, null=True, blank=True)
    ip_address = models.CharField(max_length=45)
    login_origin = models.CharField(max_length=255, null=True, blank=True)
    success = models.BooleanField()
    attempt_time = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'login_attempts'

class Group(models.Model):
    id = models.AutoField(primary_key=True)
    group_name = models.CharField(max_length=50, unique=True)

    class Meta:
        db_table = 'groups'

class UserGroup(models.Model):
    user = models.ForeignKey('User', on_delete=models.CASCADE)
    group = models.ForeignKey('Group', on_delete=models.CASCADE)

    class Meta:
        db_table = 'user_groups'
        unique_together = ('user', 'group')

class Building(models.Model):
    id = models.AutoField(primary_key=True)
    building_uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    building_name = models.CharField(max_length=255)
    description = models.TextField(null=True, blank=True)

    class Meta:
        db_table = 'buildings'

class Device(models.Model):
    id = models.AutoField(primary_key=True)
    device_uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    building = models.ForeignKey('Building', on_delete=models.RESTRICT)
    device_name = models.CharField(max_length=255)
    device_type = models.CharField(max_length=50, null=True, blank=True)
    description = models.TextField(null=True, blank=True)

    class Meta:
        db_table = 'devices'
        unique_together = ('building', 'device_name')

class Ticket(models.Model):
    id = models.AutoField(primary_key=True)
    ticket_number = models.CharField(max_length=50, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'tickets'

class TicketEntry(models.Model):
    id = models.AutoField(primary_key=True)
    user = models.ForeignKey('User', on_delete=models.CASCADE)
    ticket = models.ForeignKey('Ticket', on_delete=models.CASCADE)
    job_name = models.CharField(max_length=255)
    job_start_date = models.DateField(auto_now_add=True)
    job_start_time = models.TimeField(auto_now_add=True)
    job_end_time = models.TimeField(null=True, blank=True)
    job_duration = models.DurationField(null=True, blank=True)
    job_materials_needed = models.TextField(null=True, blank=True)
    job_access_needed = models.TextField(null=True, blank=True)
    job_programming_changes = models.TextField(null=True, blank=True)
    job_followup_required = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'ticket_entries'

class TicketMiscEntry(models.Model):
    id = models.AutoField(primary_key=True)
    user = models.ForeignKey('User', on_delete=models.CASCADE)
    misc_name = models.CharField(max_length=255)
    misc_start_date = models.DateField(auto_now_add=True)
    misc_start_time = models.TimeField(auto_now_add=True)
    misc_end_time = models.TimeField(null=True, blank=True)
    misc_duration = models.DurationField(null=True, blank=True)
    misc_details = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'ticket_misc_entries'

class TicketEntryDevice(models.Model):
    entry = models.ForeignKey('TicketEntry', on_delete=models.CASCADE)
    device = models.ForeignKey('Device', on_delete=models.RESTRICT)

    class Meta:
        db_table = 'ticket_entry_devices'
        unique_together = ('entry', 'device')

class Notification(models.Model):
    id = models.AutoField(primary_key=True)
    user = models.ForeignKey('User', null=True, blank=True, on_delete=models.SET_NULL)
    group = models.ForeignKey('Group', null=True, blank=True, on_delete=models.SET_NULL)
    title = models.CharField(max_length=255)
    message = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'notifications'

class Alert(models.Model):
    id = models.AutoField(primary_key=True)
    user = models.ForeignKey('User', null=True, blank=True, on_delete=models.SET_NULL)
    group = models.ForeignKey('Group', null=True, blank=True, on_delete=models.SET_NULL)
    entry = models.ForeignKey('TicketEntry', null=True, blank=True, on_delete=models.SET_NULL)
    alert_type = models.CharField(max_length=50)
    severity = models.CharField(max_length=10, choices=[('low', 'low'), ('medium', 'medium'), ('high', 'high'), ('critical', 'critical')])
    message = models.TextField()
    is_resolved = models.BooleanField(default=False)
    resolved_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'alerts'

class History(models.Model):
    id = models.AutoField(primary_key=True)
    table_name = models.CharField(max_length=255)
    record_id = models.BigIntegerField()
    action = models.CharField(max_length=50)
    user = models.ForeignKey('User', on_delete=models.CASCADE)
    changes = models.JSONField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'history'

class DailyAlertCount(models.Model):
    user_id = models.UUIDField()
    alert_date = models.DateField()
    alert_count = models.BigIntegerField()

    class Meta:
        managed = False
        db_table = 'daily_alert_counts'
