namespace KLOP.Platform.Domain;

public sealed class LoginCandidate
{
    public long UserId { get; set; }
    public string DisplayName { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public bool IsActive { get; set; }
    public DateTime? EmailVerifiedAtUtc { get; set; }
    public DateTime? LockoutUntilUtc { get; set; }
}

public sealed class Profile
{
    public long UserId { get; set; }
    public string Email { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public DateTime? EmailVerifiedAtUtc { get; set; }
}