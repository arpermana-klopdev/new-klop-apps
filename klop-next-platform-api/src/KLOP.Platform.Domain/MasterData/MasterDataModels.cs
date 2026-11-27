namespace KLOP.Platform.Domain;

public sealed class OrganizationType
{
    public long OrganizationTypeId { get; set; }
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public string CountryCode { get; set; } = "";
}

public sealed class ConfigurationEntry
{
    public string ConfigurationKey { get; set; } = "";
    public string? ConfigurationValue { get; set; }
    public string ValueType { get; set; } = "";
    public string StorageType { get; set; } = "";
}