namespace KLOP.Platform.Application;

public interface IVerificationEmailSender
{
    Task Send(string email, long userId, string verificationCode, CancellationToken cancellationToken);
}