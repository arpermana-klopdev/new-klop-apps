import { getDocument, GlobalWorkerOptions } from "pdfjs-dist";
import type { PDFDocumentLoadingTask } from "pdfjs-dist";
import pdfWorkerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";
import { useEffect, useRef, useState } from "react";
import "../../styles/terms-document.css";

GlobalWorkerOptions.workerSrc = pdfWorkerUrl;

type PdfViewerState = "loading" | "ready" | "error";

export function TermsPdfViewer({
  documentUrl,
  documentTitle,
  onDocumentLoad,
  onDocumentError,
}: {
  documentUrl: string;
  documentTitle: string;
  onDocumentLoad: () => void;
  onDocumentError: () => void;
}) {
  const viewerRef = useRef<HTMLDivElement>(null);
  const pagesRef = useRef<HTMLDivElement>(null);
  const [state, setState] = useState<PdfViewerState>("loading");
  const [pageCount, setPageCount] = useState(0);

  useEffect(() => {
    let active = true;
    let loadingTask: PDFDocumentLoadingTask | null = null;
    const renderTasks: Array<{ cancel: () => void }> = [];
    setState("loading");
    setPageCount(0);
    pagesRef.current?.replaceChildren();

    async function renderDocument() {
      try {
        loadingTask = getDocument({ url: documentUrl });
        const pdf = await loadingTask.promise;
        if (!active) return;

        const viewer = viewerRef.current;
        const pagesContainer = pagesRef.current;
        if (!viewer || !pagesContainer || pdf.numPages < 1) {
          throw new Error("The Terms PDF has no renderable pages.");
        }

        setPageCount(pdf.numPages);
        const outputScale = Math.min(window.devicePixelRatio || 1, 2);
        const availableWidth = Math.max(1, viewer.clientWidth - 32);

        for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber += 1) {
          const page = await pdf.getPage(pageNumber);
          if (!active) return;

          const baseViewport = page.getViewport({ scale: 1 });
          const scale = Math.min(1.5, availableWidth / baseViewport.width);
          const viewport = page.getViewport({ scale });
          const canvas = window.document.createElement("canvas");
          canvas.className = "auth-terms-pdf-page";
          canvas.width = Math.ceil(viewport.width * outputScale);
          canvas.height = Math.ceil(viewport.height * outputScale);
          canvas.style.width = `${viewport.width}px`;
          canvas.style.height = `${viewport.height}px`;
          canvas.setAttribute("aria-hidden", "true");

          const canvasContext = canvas.getContext("2d", { alpha: false });
          if (!canvasContext) {
            throw new Error(`Could not create a canvas for Terms PDF page ${pageNumber}.`);
          }

          const renderTask = page.render({
            canvas,
            canvasContext,
            viewport,
            transform: [outputScale, 0, 0, outputScale, 0, 0],
          });
          renderTasks.push(renderTask);
          await renderTask.promise;
          renderTasks.splice(renderTasks.indexOf(renderTask), 1);
          if (!active) return;

          const textContent = await page.getTextContent();
          const pageContainer = window.document.createElement("section");
          pageContainer.className = "auth-terms-pdf-page-container";
          pageContainer.setAttribute("role", "group");
          pageContainer.setAttribute("aria-label", `Page ${pageNumber} of ${pdf.numPages}`);
          pageContainer.append(canvas);

          const accessibleText = window.document.createElement("p");
          accessibleText.className = "auth-terms-pdf-accessible-text";
          accessibleText.textContent = textContent.items
            .map((item) => ("str" in item ? item.str : ""))
            .filter(Boolean)
            .join(" ");
          pageContainer.append(accessibleText);
          pagesContainer.append(pageContainer);
          page.cleanup();
        }

        if (!active) return;
        setState("ready");
        onDocumentLoad();
      } catch {
        if (!active) return;
        setState("error");
        onDocumentError();
      }
    }

    void renderDocument();

    return () => {
      active = false;
      renderTasks.forEach((task) => task.cancel());
      if (loadingTask) void loadingTask.destroy().catch(() => undefined);
      pagesRef.current?.replaceChildren();
    };
  }, [documentUrl, onDocumentError, onDocumentLoad]);

  return (
    <div
      ref={viewerRef}
      className="auth-terms-document-viewer"
      role="region"
      aria-label={`${documentTitle} PDF pages`}
      aria-busy={state === "loading"}
      tabIndex={0}
    >
      {state === "loading" && <p role="status">Loading and rendering the Terms PDF…</p>}
      {state === "error" && (
        <p role="alert">We couldn&apos;t display the Terms PDF. Please try again.</p>
      )}
      <div ref={pagesRef} className="auth-terms-pdf-pages" />
      {state === "ready" && (
        <p className="auth-terms-pdf-ready" role="status">
          All {pageCount} pages are ready to review.
        </p>
      )}
    </div>
  );
}
