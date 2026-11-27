import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ApiRequestError } from "../src/api/client";
import type { RolePermissionMatrixResponse, RolePermissionMatrixValidationResponse } from "../src/api/contracts";
import {
  getRolePermissionMatrixAccess,
  getRolePermissionMatrix,
  getRolePermissionHistory,
  validateRolePermissionChanges,
  saveRolePermissionChanges,
} from "../src/api/rolePermissionMatrix";
import { RolePermissionMatrixPage } from "../src/features/setup/RolePermissionMatrixPage";

vi.mock("../src/api/rolePermissionMatrix", () => ({
  getRolePermissionMatrixAccess: vi.fn(),
  getRolePermissionMatrix: vi.fn(),
  getRolePermissionHistory: vi.fn(),
  validateRolePermissionChanges: vi.fn(),
  saveRolePermissionChanges: vi.fn(),
}));

const matrix: RolePermissionMatrixResponse = {
  columns: [{
    roleId: 3, roleCode: "OWNER", roleName: "Owner", scopeCode: "TENANT",
    tenantTypeId: 2, tenantTypeCode: "ORGANIZATION", isAssignable: false,
  }],
  rows: [{
    permissionId: 7, module: "tenant", resource: "members", action: "remove",
    permissionCode: "tenant.members.remove", permissionName: "Remove members",
    permissionDescription: "Remove a member", scopeCode: "TENANT", readinessStatus: "ACTIVE",
    isAccountPolicy: false, accountPolicy: null,
    cells: [{
      roleId: 3, roleCode: "OWNER", scopeCode: "TENANT",
      tenantTypeId: 2, tenantTypeCode: "ORGANIZATION", configuredGrant: false,
      effectiveAllowed: false, isEditable: true, restrictionReason: null,
      concurrencyVersion: "AAECAwQFBgc=",
    }],
  }],
};

function renderMatrix() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(<QueryClientProvider client={queryClient}>
    <MemoryRouter><RolePermissionMatrixPage /></MemoryRouter>
  </QueryClientProvider>);
}

async function prepareChange() {
  const cell = await screen.findByRole("checkbox", { name: "tenant.members.remove OWNER ORGANIZATION" });
  fireEvent.click(cell);
  const reason = screen.getByRole("textbox", { name: /Change reason/ });
  fireEvent.change(reason, { target: { value: "Approved change reason" } });
  return { cell, reason };
}

describe("RolePermissionMatrixPage API integration", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    vi.mocked(getRolePermissionMatrixAccess).mockResolvedValue({ canRead: true, canUpdate: true });
    vi.mocked(getRolePermissionMatrix).mockResolvedValue(matrix);
    vi.mocked(getRolePermissionHistory).mockResolvedValue([]);
    vi.mocked(validateRolePermissionChanges).mockResolvedValue({ isValid: true, issues: [] });
  });

  it("does not request matrix or history without read permission", async () => {
    vi.mocked(getRolePermissionMatrixAccess).mockResolvedValue({ canRead: false, canUpdate: false });
    renderMatrix();
    expect(await screen.findByText(/do not have permission to view/)).toBeInTheDocument();
    expect(getRolePermissionMatrix).not.toHaveBeenCalled();
    expect(getRolePermissionHistory).not.toHaveBeenCalled();
  });

  it("locks editing during validation and requires a new review if the reason changes", async () => {
    let resolve!: (response: RolePermissionMatrixValidationResponse) => void;
    vi.mocked(validateRolePermissionChanges).mockReturnValue(new Promise((done) => { resolve = done; }));
    renderMatrix();
    const { cell, reason } = await prepareChange();
    fireEvent.click(screen.getByRole("button", { name: "Review Changes" }));
    await waitFor(() => expect(validateRolePermissionChanges).toHaveBeenCalledOnce());
    expect(cell).toBeDisabled();
    expect(reason).toBeDisabled();
    expect(screen.getByRole("button", { name: "Confirm & Save" })).toBeDisabled();
    await act(async () => resolve({ isValid: true, issues: [] }));
    await waitFor(() => expect(screen.getByRole("button", { name: "Confirm & Save" })).toBeEnabled());
    fireEvent.change(reason, { target: { value: "Different change reason" } });
    expect(screen.getByRole("button", { name: "Confirm & Save" })).toBeDisabled();
    expect(saveRolePermissionChanges).not.toHaveBeenCalled();
  });

  it("discards stale changes and reloads the server matrix before a new review", async () => {
    vi.mocked(saveRolePermissionChanges).mockRejectedValue(new ApiRequestError(
      "STALE_PERMISSION_MATRIX", "Refresh and try again.", 409,
    ));
    renderMatrix();
    const { cell } = await prepareChange();
    fireEvent.click(screen.getByRole("button", { name: "Review Changes" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "Confirm & Save" })).toBeEnabled());
    fireEvent.click(screen.getByRole("button", { name: "Confirm & Save" }));
    fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Confirm & Save" }));
    const reload = await screen.findByRole("button", { name: /Reload Matrix/ });
    expect(cell).toBeDisabled();
    expect(vi.mocked(saveRolePermissionChanges).mock.calls[0]?.[0]).toEqual({
      reason: "Approved change reason",
      changes: [{ permissionId: 7, roleId: 3, tenantTypeId: 2, isGranted: true, concurrencyVersion: "AAECAwQFBgc=" }],
    });
    fireEvent.click(reload);
    await waitFor(() => expect(getRolePermissionMatrix).toHaveBeenCalledTimes(2));
    await waitFor(() => expect(screen.getByRole("checkbox")).not.toBeChecked());
    expect(screen.queryByRole("button", { name: "Confirm & Save" })).not.toBeInTheDocument();
  });
});
