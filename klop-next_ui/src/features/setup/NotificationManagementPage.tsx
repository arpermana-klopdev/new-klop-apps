import { useMemo, useRef, useState, type KeyboardEvent } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import {
  createNotificationDraft,
  getNotificationChannels,
  getNotificationHistory,
  getNotificationPermissions,
  getNotificationReadiness,
  getNotificationTemplate,
  getNotificationTemplates,
  previewNotificationDraft,
  transitionNotificationVersion,
  updateNotificationDraft,
  type NotificationDecisionRequest,
  type NotificationTemplate,
  type NotificationTemplateVersion,
} from "../../api/notifications";
import { toApiRequestError } from "../../api/client";
import { Button, Notice, PageHeading, Skeleton, StatusBadge } from "../../components/ui";

type TabId = "templates" | "channels" | "history" | "settings";

const tabs: { id: TabId; label: string }[] = [
  { id: "templates", label: "Templates" },
  { id: "channels", label: "Channels" },
  { id: "history", label: "History" },
  { id: "settings", label: "Settings" },
];

type MutationCommand =
  | { action: "create"; template: NotificationTemplate; subject: string; body: string }
  | { action: "update"; version: NotificationTemplateVersion; subject: string; body: string }
  | {
      action: "transition";
      version: NotificationTemplateVersion;
      transition: "submit" | "approval" | "activate" | "archive";
      decision: string;
    };

function requestFor(version: NotificationTemplateVersion, decision: string): NotificationDecisionRequest {
  return {
    decision,
    concurrencyVersion: version.concurrencyVersion,
    note: null,
  };
}

export function NotificationManagementPage() {
  const [activeTab, setActiveTab] = useState<TabId>("templates");
  const [selectedTemplateId, setSelectedTemplateId] = useState<string | null>(null);
  const [selectedVersionId, setSelectedVersionId] = useState<string | null>(null);
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");
  const [preview, setPreview] = useState<{ subject: string; body: string } | null>(null);
  const [operationMessage, setOperationMessage] = useState<string | null>(null);
  const tabRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const queryClient = useQueryClient();

  const permissionsQuery = useQuery({
    queryKey: ["platform-notifications", "permissions"],
    queryFn: getNotificationPermissions,
    retry: false,
  });
  const permissions = permissionsQuery.data?.permissions ?? [];
  const can = (permission: string) => permissionsQuery.isSuccess && permissions.includes(permission);
  const templatesQuery = useQuery({
    queryKey: ["platform-notifications", "templates"],
    queryFn: getNotificationTemplates,
    enabled: can("platform.notifications.read"),
    retry: false,
  });
  const templates = templatesQuery.data ?? [];
  const selectedTemplate = templates.find((template) => template.templateId === selectedTemplateId) ?? null;
  const detailQuery = useQuery({
    queryKey: ["platform-notifications", "template", selectedTemplateId],
    queryFn: () => getNotificationTemplate(selectedTemplateId!),
    enabled: can("platform.notifications.read") && selectedTemplateId !== null,
    retry: false,
  });
  const selectedVersion = detailQuery.data?.versions.find((version) => version.versionId === selectedVersionId) ?? null;
  const channelsQuery = useQuery({
    queryKey: ["platform-notifications", "channels"],
    queryFn: getNotificationChannels,
    enabled: activeTab === "channels" && can("platform.notifications.read"),
    retry: false,
  });
  const historyQuery = useQuery({
    queryKey: ["platform-notifications", "history"],
    queryFn: () => getNotificationHistory(),
    enabled: activeTab === "history" && can("platform.notifications.history"),
    retry: false,
  });
  const readinessQuery = useQuery({
    queryKey: ["platform-notifications", "settings"],
    queryFn: getNotificationReadiness,
    enabled: activeTab === "settings" && can("platform.notifications.settings.read"),
    retry: false,
  });

  const mutation = useMutation({
    mutationFn: async (command: MutationCommand) => {
      if (command.action === "create") {
        return createNotificationDraft({
          templateCode: command.template.templateCode,
          displayName: command.template.displayName,
          channelCode: command.template.channelCode,
          localeCode: command.template.localeCode,
          subject: command.subject,
          body: command.body,
        });
      }
      if (command.action === "update") {
        return updateNotificationDraft(command.version.versionId, {
          subject: command.subject,
          body: command.body,
          concurrencyVersion: command.version.concurrencyVersion,
        });
      }
      return transitionNotificationVersion(
        command.version.versionId,
        command.transition,
        requestFor(command.version, command.decision),
      );
    },
    onSuccess: async (result, command) => {
      setOperationMessage(command.action === "transition"
        ? "Template version updated."
        : "Draft saved.");
      setPreview(null);
      if (command.action === "create" && "versionId" in result) {
        setSelectedTemplateId(result.templateId);
        setSelectedVersionId(result.versionId);
      }
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["platform-notifications", "templates"] }),
        queryClient.invalidateQueries({ queryKey: ["platform-notifications", "template"] }),
      ]);
    },
    onError: (error: unknown) => {
      const apiError = toApiRequestError(error);
      setOperationMessage(apiError.status === 409
        ? "This version changed since it was loaded. Refresh its details before trying again."
        : apiError.message);
    },
  });

  const versionOrder = useMemo(
    () => [...(detailQuery.data?.versions ?? [])].sort((a, b) => b.versionNumber - a.versionNumber),
    [detailQuery.data],
  );

  function chooseTemplate(template: NotificationTemplate) {
    setSelectedTemplateId(template.templateId);
    setSelectedVersionId(null);
    setSubject("");
    setBody("");
    setPreview(null);
    setOperationMessage(null);
  }

  function chooseVersion(version: NotificationTemplateVersion) {
    setSelectedVersionId(version.versionId);
    setSubject(version.subject);
    setBody(version.body);
    setPreview(null);
    setOperationMessage(null);
  }

  function handleTabKeyDown(event: KeyboardEvent<HTMLButtonElement>, currentIndex: number) {
    let nextIndex: number | null = null;
    if (event.key === "ArrowRight") nextIndex = (currentIndex + 1) % tabs.length;
    if (event.key === "ArrowLeft") nextIndex = (currentIndex + tabs.length - 1) % tabs.length;
    if (event.key === "Home") nextIndex = 0;
    if (event.key === "End") nextIndex = tabs.length - 1;
    if (nextIndex !== null) {
      event.preventDefault();
      tabRefs.current[nextIndex]?.focus();
      setActiveTab(tabs[nextIndex]?.id ?? "templates");
    }
  }

  function renderPermissionState(permission: string) {
    if (permissionsQuery.isPending) return <div role="status" aria-label="Checking notification permissions"><Skeleton className="h-10" /></div>;
    if (permissionsQuery.isError) {
      return (
        <Notice kind="error">
          Notification permissions could not be verified.
          <Button className="ml-3" size="sm" variant="secondary" onClick={() => void permissionsQuery.refetch()}>
            Retry
          </Button>
        </Notice>
      );
    }
    if (!can(permission)) return <Notice kind="info">This tab requires an explicit PLATFORM notification permission.</Notice>;
    return null;
  }

  function renderLoadError(label: string, retry: () => void) {
    return (
      <Notice kind="error">
        {label} could not be loaded.
        <Button className="ml-3" size="sm" variant="secondary" onClick={() => void retry()}>Retry</Button>
      </Notice>
    );
  }

  const tabPermission: Record<TabId, string> = {
    templates: "platform.notifications.read",
    channels: "platform.notifications.read",
    history: "platform.notifications.history",
    settings: "platform.notifications.settings.read",
  };

  return (
    <>
      <PageHeading
        eyebrow="Platform administration / Platform Setup"
        title="Notifications"
        description="Versioned email templates, channel readiness, delivery audit, and safe SMTP readiness."
        action={<Link to="/platform-setup"><Button variant="secondary">Platform Setup</Button></Link>}
      />
      <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-soft dark:border-slate-800 dark:bg-slate-900 sm:p-6">
        <div className="mb-5 flex items-center justify-between gap-3">
          <h2 className="text-sm font-bold text-slate-950 dark:text-white">Notification management</h2>
          <StatusBadge value="Email only" />
        </div>
        <div role="tablist" aria-label="Notification management sections" className="mb-5 flex flex-wrap gap-2">
          {tabs.map((tab, index) => (
            <button
              key={tab.id}
              ref={(element) => { tabRefs.current[index] = element; }}
              type="button"
              role="tab"
              id={`notification-tab-${tab.id}`}
              aria-selected={activeTab === tab.id}
              aria-controls={`notification-panel-${tab.id}`}
              tabIndex={activeTab === tab.id ? 0 : -1}
              onClick={() => setActiveTab(tab.id)}
              onKeyDown={(event) => handleTabKeyDown(event, index)}
              className="rounded-full border border-slate-200 px-3 py-1.5 text-sm font-medium text-slate-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 aria-selected:border-brand-600 aria-selected:bg-brand-50 aria-selected:text-brand-800 dark:border-slate-700 dark:text-slate-200 dark:aria-selected:bg-slate-800"
            >
              {tab.label}
            </button>
          ))}
        </div>

        <section
          role="tabpanel"
          id={`notification-panel-${activeTab}`}
          aria-labelledby={`notification-tab-${activeTab}`}
          className="space-y-4"
        >
          {renderPermissionState(tabPermission[activeTab])}

          {activeTab === "templates" && can("platform.notifications.read") && (
            <>
              {templatesQuery.isPending && <div role="status" aria-label="Loading templates"><Skeleton className="h-24" /></div>}
              {templatesQuery.isError && renderLoadError("Template catalog", () => void templatesQuery.refetch())}
              {templatesQuery.data && templates.length === 0 && <Notice kind="info">No notification templates are configured.</Notice>}
              {templates.map((template) => (
                <button
                  type="button"
                  key={template.templateId}
                  onClick={() => chooseTemplate(template)}
                  aria-pressed={selectedTemplateId === template.templateId}
                  className="flex w-full items-center justify-between gap-4 rounded-xl border border-slate-200 p-4 text-left hover:border-brand-400 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 dark:border-slate-700"
                >
                  <span>
                    <span className="block font-semibold">{template.displayName}</span>
                    <span className="block font-mono text-xs text-slate-500">
                      {template.templateCode} · {template.channelCode} · {template.localeCode}
                    </span>
                  </span>
                  <span className="text-right text-xs text-slate-500">
                    {template.activeVersionNumber ? `Active v${template.activeVersionNumber}` : "No active version"}
                  </span>
                </button>
              ))}
              {detailQuery.isPending && selectedTemplateId && <div role="status" aria-label="Loading versions"><Skeleton className="h-24" /></div>}
              {detailQuery.isError && renderLoadError("Template details", () => void detailQuery.refetch())}
              {selectedTemplate && detailQuery.data && (
                <div className="space-y-4 rounded-xl border border-slate-200 p-4 dark:border-slate-700">
                  <h3 className="font-semibold">{detailQuery.data.displayName} versions</h3>
                  {versionOrder.length === 0 && <p className="text-sm text-slate-500">No versions are available.</p>}
                  <div className="flex flex-wrap gap-2">
                    {versionOrder.map((version) => (
                      <Button
                        key={version.versionId}
                        variant={selectedVersionId === version.versionId ? "primary" : "secondary"}
                        onClick={() => chooseVersion(version)}
                      >
                        v{version.versionNumber} · {version.status}
                      </Button>
                    ))}
                  </div>
                  {selectedVersion && (
                    <div className="space-y-3">
                      {selectedVersion.status === "DRAFT" && can("platform.notifications.draft.edit") ? (
                        <form className="space-y-3" onSubmit={(event) => {
                          event.preventDefault();
                          mutation.mutate({ action: "update", version: selectedVersion, subject, body });
                        }}>
                          <label className="block text-sm font-medium">
                            Subject
                            <input className="mt-1 w-full rounded-lg border border-slate-300 p-2 dark:bg-slate-950" value={subject} onChange={(event) => setSubject(event.target.value)} />
                          </label>
                          <label className="block text-sm font-medium">
                            Plain-text body
                            <textarea className="mt-1 min-h-32 w-full rounded-lg border border-slate-300 p-2 dark:bg-slate-950" value={body} onChange={(event) => setBody(event.target.value)} />
                          </label>
                          <Button type="submit" disabled={mutation.isPending}>Save draft</Button>
                        </form>
                      ) : (
                        <div>
                          <p className="text-sm font-medium">{selectedVersion.subject}</p>
                          <pre className="mt-2 whitespace-pre-wrap rounded-lg bg-slate-50 p-3 text-sm dark:bg-slate-950">{selectedVersion.body}</pre>
                        </div>
                      )}
                      <div className="flex flex-wrap gap-2">
                        {can("platform.notifications.draft.preview") && (
                          <Button variant="secondary" disabled={mutation.isPending} onClick={async () => {
                            try {
                              setPreview(await previewNotificationDraft(selectedVersion.versionId));
                              setOperationMessage(null);
                            } catch (error) {
                              setOperationMessage(toApiRequestError(error).message);
                            }
                          }}>Preview with synthetic values</Button>
                        )}
                        {selectedVersion.status === "DRAFT" && can("platform.notifications.submit") && (
                          <Button disabled={mutation.isPending} onClick={() => mutation.mutate({
                            action: "transition", version: selectedVersion, transition: "submit", decision: "SUBMIT",
                          })}>Submit for approval</Button>
                        )}
                        {selectedVersion.status === "PENDING_APPROVAL" && can("platform.notifications.approve") && (
                          <>
                            <Button disabled={mutation.isPending} onClick={() => mutation.mutate({
                              action: "transition", version: selectedVersion, transition: "approval", decision: "APPROVE",
                            })}>Approve</Button>
                            <Button variant="secondary" disabled={mutation.isPending} onClick={() => mutation.mutate({
                              action: "transition", version: selectedVersion, transition: "approval", decision: "REJECT",
                            })}>Reject to draft</Button>
                          </>
                        )}
                        {selectedVersion.status === "APPROVED" && can("platform.notifications.activate") && (
                          <Button disabled={mutation.isPending} onClick={() => mutation.mutate({
                            action: "transition", version: selectedVersion, transition: "activate", decision: "ACTIVATE",
                          })}>Activate</Button>
                        )}
                        {selectedVersion.status === "ACTIVE" && can("platform.notifications.archive") && (
                          <Button variant="secondary" disabled={mutation.isPending} onClick={() => mutation.mutate({
                            action: "transition", version: selectedVersion, transition: "archive", decision: "ARCHIVE",
                          })}>Archive</Button>
                        )}
                      </div>
                    </div>
                  )}
                  {can("platform.notifications.draft.create") && (
                    <form className="space-y-3 border-t border-slate-200 pt-4 dark:border-slate-700" onSubmit={(event) => {
                      event.preventDefault();
                      if (selectedTemplate) mutation.mutate({ action: "create", template: selectedTemplate, subject, body });
                    }}>
                      <h4 className="font-medium">Create a new draft version</h4>
                      <label className="block text-sm font-medium">
                        Subject
                        <input className="mt-1 w-full rounded-lg border border-slate-300 p-2 dark:bg-slate-950" value={subject} onChange={(event) => setSubject(event.target.value)} />
                      </label>
                      <label className="block text-sm font-medium">
                        Plain-text body
                        <textarea className="mt-1 min-h-32 w-full rounded-lg border border-slate-300 p-2 dark:bg-slate-950" value={body} onChange={(event) => setBody(event.target.value)} />
                      </label>
                      <Button type="submit" disabled={mutation.isPending}>Create draft version</Button>
                    </form>
                  )}
                </div>
              )}
              {operationMessage && <Notice kind={operationMessage.includes("changed since") ? "error" : "info"}>{operationMessage}</Notice>}
              {preview && (
                <section aria-label="Notification preview" className="rounded-xl border border-brand-200 p-4 dark:border-brand-800">
                  <h3 className="font-semibold">Synthetic preview</h3>
                  <p className="mt-2 font-medium">{preview.subject}</p>
                  <pre className="mt-2 whitespace-pre-wrap text-sm">{preview.body}</pre>
                  <p className="mt-3 text-xs text-slate-500">Preview values are synthetic and nonfunctional. No message was sent.</p>
                </section>
              )}
            </>
          )}

          {activeTab === "channels" && can("platform.notifications.read") && (
            <>
              {channelsQuery.isPending && <div role="status" aria-label="Loading channels"><Skeleton className="h-20" /></div>}
              {channelsQuery.isError && renderLoadError("Channel catalog", () => void channelsQuery.refetch())}
              {channelsQuery.data?.length === 0 && <Notice kind="info">No notification channels are configured.</Notice>}
              {channelsQuery.data?.map((channel) => (
                <article key={channel.channelCode} className="flex items-center justify-between rounded-xl border border-slate-200 p-4 dark:border-slate-700">
                  <div><h3 className="font-semibold">{channel.displayName}</h3><p className="text-sm text-slate-500">{channel.readiness}</p></div>
                  <StatusBadge value={channel.isEnabled ? channel.status : "Disabled"} />
                </article>
              ))}
              <Notice kind="info">Planned, not enabled: SMS, WhatsApp, and in-app notifications. No send flows are wired for these channels.</Notice>
            </>
          )}

          {activeTab === "history" && can("platform.notifications.history") && (
            <>
              {historyQuery.isPending && <div role="status" aria-label="Loading delivery history"><Skeleton className="h-20" /></div>}
              {historyQuery.isError && renderLoadError("Delivery history", () => void historyQuery.refetch())}
              {historyQuery.data?.items.length === 0 && <Notice kind="info">No delivery attempts are recorded.</Notice>}
              {historyQuery.data && historyQuery.data.items.length > 0 && (
                <div className="overflow-x-auto">
                  <table className="w-full text-left text-sm">
                    <thead><tr><th className="p-2">Template</th><th className="p-2">Channel</th><th className="p-2">Outcome</th><th className="p-2">Time (UTC)</th><th className="p-2">Correlation</th></tr></thead>
                    <tbody>{historyQuery.data.items.map((item) => (
                      <tr key={item.deliveryId} className="border-t border-slate-200 dark:border-slate-700">
                        <td className="p-2">{item.templateCode} · {item.templateVersion}</td>
                        <td className="p-2">{item.channelCode}</td>
                        <td className="p-2">{item.outcome}{item.safeErrorCategory ? ` · ${item.safeErrorCategory}` : ""}</td>
                        <td className="p-2">{item.occurredAtUtc}</td>
                        <td className="p-2 font-mono text-xs">{item.correlationId}</td>
                      </tr>
                    ))}</tbody>
                  </table>
                  <p className="mt-3 text-xs text-slate-500">Provider acceptance is not confirmation of inbox delivery. Recipient addresses and message content are not shown.</p>
                </div>
              )}
            </>
          )}

          {activeTab === "settings" && can("platform.notifications.settings.read") && (
            <>
              {readinessQuery.isPending && <div role="status" aria-label="Loading SMTP readiness"><Skeleton className="h-20" /></div>}
              {readinessQuery.isError && renderLoadError("SMTP readiness", () => void readinessQuery.refetch())}
              {readinessQuery.data && (
                <dl className="grid gap-3 sm:grid-cols-2">
                  {[
                    { label: "SMTP host configured", ready: readinessQuery.data.smtpHostConfigured },
                    { label: "SMTP port configured", ready: readinessQuery.data.smtpPortConfigured },
                    { label: "Sender configured", ready: readinessQuery.data.senderConfigured },
                    { label: "TLS required", ready: readinessQuery.data.tlsRequired },
                    { label: "Key Vault credentials configured", ready: readinessQuery.data.credentialsConfigured },
                    { label: "Template rollout enabled", ready: readinessQuery.data.templateRolloutEnabled },
                  ].map(({ label, ready }) => (
                    <div key={label} className="rounded-lg border border-slate-200 p-3 dark:border-slate-700">
                      <dt className="text-xs text-slate-500">{label}</dt>
                      <dd className="mt-1 font-medium">{ready ? "Yes" : "No"}</dd>
                    </div>
                  ))}
                  <div className="rounded-lg border border-slate-200 p-3 dark:border-slate-700">
                    <dt className="text-xs text-slate-500">Verification lifetime</dt>
                    <dd className="mt-1 font-medium">{readinessQuery.data.verificationLifetimeStatus}</dd>
                  </div>
                </dl>
              )}
              <Notice kind="info">SMTP values and secrets are not displayed or editable here. Production TLS remains required. No test-send or network probe is available.</Notice>
            </>
          )}
        </section>
      </section>
    </>
  );
}
