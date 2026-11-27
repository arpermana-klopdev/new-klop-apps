namespace KLOP.Platform.Application;

public interface IAccessTokenIssuer
{
    AccessResult Issue(long userId, Guid sessionId);
}