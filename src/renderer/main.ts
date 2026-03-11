import { mount } from "svelte";
import App from "./App.svelte";
import { Electroview } from "electrobun/view";
import type { AppRPCType } from "../shared/types";

type LogCallback = (msg: string) => void;
type DataRowCallback = (addr: number, hex: string) => void;
type ProgressCallback = (addr: number, total: number, pct: number) => void;
type ReadCompleteCallback = (totalBytes: number, filename: string) => void;
type ReadErrorCallback = (msg: string) => void;

let _onLog: LogCallback | null = null;
let _onDataRow: DataRowCallback | null = null;
let _onProgress: ProgressCallback | null = null;
let _onReadComplete: ReadCompleteCallback | null = null;
let _onReadError: ReadErrorCallback | null = null;

export function setLogHandler(cb: LogCallback) { _onLog = cb; }
export function setDataRowHandler(cb: DataRowCallback) { _onDataRow = cb; }
export function setProgressHandler(cb: ProgressCallback) { _onProgress = cb; }
export function setReadCompleteHandler(cb: ReadCompleteCallback) { _onReadComplete = cb; }
export function setReadErrorHandler(cb: ReadErrorCallback) { _onReadError = cb; }

export const rpcInstance = Electroview.defineRPC<AppRPCType>({
  handlers: {
    requests: {},
    messages: {
      log: ({ message }) => _onLog?.(message),
      dataRow: ({ address, hex }) => _onDataRow?.(address, hex),
      progress: ({ address, totalBytes, percent }) => _onProgress?.(address, totalBytes, percent),
      readComplete: ({ totalBytes, filename }) => _onReadComplete?.(totalBytes, filename),
      readError: ({ message }) => _onReadError?.(message),
    },
  },
});

export const electroview = new Electroview({ rpc: rpcInstance });

mount(App, { target: document.body });
