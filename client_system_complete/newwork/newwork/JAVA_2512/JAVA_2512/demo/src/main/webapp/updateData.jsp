<%@ page language="java" contentType="text/html; charset=UTF-8"
    pageEncoding="UTF-8"%>
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<title>Update Data Sync</title>
<%
	pageContext.setAttribute("APP_PATH", request.getContextPath());
%>
<script type="text/javascript" src="${APP_PATH}/static/js/jquery-1.12.4.min.js"></script>
<link href="${APP_PATH}/static/bootstrap-3.3.7-dist/css/bootstrap.min.css" rel="stylesheet">
<link href="${APP_PATH}/static/css/bootstrap-datetimepicker.min.css" rel="stylesheet">
<script src="${APP_PATH}/static/bootstrap-3.3.7-dist/js/bootstrap.min.js"></script>
<script src="${APP_PATH}/static/js/bootstrap-datetimepicker.min.js"></script>
<script src="${APP_PATH}/static/js/bootstrap-datetimepicker.zh-CN.js"></script>
<style type="text/css">
	body {
		background: #f6f8fb;
	}
	.sync-card {
		margin-top: 24px;
		background: #fff;
		border: 1px solid #dfe6ee;
		border-radius: 8px;
		padding: 20px 22px;
		box-shadow: 0 2px 10px rgba(0, 0, 0, 0.04);
	}
	.sync-title {
		font-size: 22px;
		font-weight: 700;
		color: #1f2d3d;
		margin-bottom: 8px;
	}
	.sync-subtitle {
		color: #5f6b7a;
		font-size: 13px;
		margin-bottom: 18px;
	}
	.result-box {
		margin-top: 14px;
		padding: 12px 14px;
		border-radius: 6px;
		border: 1px solid #d9e2ec;
		background: #fbfdff;
		font-size: 13px;
		line-height: 1.6;
		word-break: break-word;
		white-space: normal;
	}
	.result-success {
		border-color: #b9dfc3;
		background: #f4fff6;
	}
	.result-fail {
		border-color: #e8b8b8;
		background: #fff6f6;
	}
	.run-state {
		margin-top: 10px;
		font-size: 13px;
		font-weight: 600;
		color: #1f2d3d;
	}
	.run-state.running {
		color: #0b63b6;
	}
	.run-state.success {
		color: #2e7d32;
	}
	.run-state.failed {
		color: #c62828;
	}
	.sync-form-row .input-group,
	.sync-form-row label,
	.sync-form-row button {
		margin-bottom: 8px;
	}
	.sync-form-row .input-group {
		margin-right: 8px;
	}
	.sync-form-row label {
		margin-right: 8px;
	}
</style>
</head>
<body>
	<div class="container">
		<div class="row">
			<div class="col-md-8 col-md-offset-2">
				<div class="sync-card">
					<div class="sync-title">updatedata</div>

					<div class="form-inline">
						<label for="syncDateInput" style="margin-right:8px;">Select Date</label>
						<div class="input-group date" id="updateDataDatePicker" style="width:220px; display:inline-table; vertical-align:middle;">
							<input type="text" id="syncDateInput" class="form-control" placeholder="yyyy-mm-dd">
							<span class="input-group-addon">
								<span class="glyphicon glyphicon-calendar"></span>
							</span>
						</div>
						<button class="btn btn-primary" id="syncStatusByDateBtn" style="margin-left:10px;">SyncStatus</button>
						<button class="btn btn-danger" id="syncDeleteByDateBtn" style="margin-left:8px;">SyncDelete</button>
					</div>

					<div id="syncStatusResult" class="result-box" style="margin-top:18px;">Status sync result yahan dikhega.</div>
					<div id="syncDeleteResult" class="result-box">Delete sync result yahan dikhega.</div>
					<div id="runStateMsg" class="run-state">Idle</div>
				</div>

				<div class="sync-card">
					<div class="sync-title">Date Range Direct Sync</div>
					<div class="sync-subtitle">From Date se To Date tak ka data direct online devices ko 50-user batch me bheja jayega. DEVICECMD use nahi hoga.</div>

					<div class="form-inline sync-form-row">
						<label for="rangeFromDateInput">From Date</label>
						<div class="input-group date" id="rangeFromDatePicker" style="width:220px; display:inline-table; vertical-align:middle;">
							<input type="text" id="rangeFromDateInput" class="form-control" placeholder="yyyy-mm-dd">
							<span class="input-group-addon">
								<span class="glyphicon glyphicon-calendar"></span>
							</span>
						</div>

						<label for="rangeToDateInput" style="margin-left:8px;">To Date</label>
						<div class="input-group date" id="rangeToDatePicker" style="width:220px; display:inline-table; vertical-align:middle;">
							<input type="text" id="rangeToDateInput" class="form-control" placeholder="yyyy-mm-dd">
							<span class="input-group-addon">
								<span class="glyphicon glyphicon-calendar"></span>
							</span>
						</div>

						<button class="btn btn-primary" id="rangeUpdateSyncBtn" style="margin-left:10px;">UpdateSync</button>
						<button class="btn btn-danger" id="rangeDeleteSyncBtn" style="margin-left:8px;">DeleteSync</button>
					</div>

					<div id="rangeSyncStatusResult" class="result-box" style="margin-top:18px;">Date range update sync result yahan dikhega.</div>
					<div id="rangeSyncDeleteResult" class="result-box">Date range delete sync result yahan dikhega.</div>
					<div id="rangeRunStateMsg" class="run-state">Idle</div>
				</div>
			</div>
		</div>
	</div>

<script type="text/javascript">
	function pad2(value){
		return value < 10 ? "0" + value : String(value);
	}

	function formatDate(date){
		return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate());
	}

	function setResult($target, isSuccess, text){
		$target.removeClass("result-success result-fail");
		$target.addClass(isSuccess ? "result-success" : "result-fail");
		$target.text(text);
	}

	function getSelectedDate(){
		return $.trim($("#syncDateInput").val());
	}

	function getRangeFromDate(){
		return $.trim($("#rangeFromDateInput").val());
	}

	function getRangeToDate(){
		return $.trim($("#rangeToDateInput").val());
	}

	function validateRangeDates(fromDate, toDate){
		if(fromDate === "" || toDate === ""){
			return "Please select both from date and to date.";
		}
		if(fromDate > toDate){
			return "From date cannot be greater than to date.";
		}
		return "";
	}

	var isSyncRunning = false;

	function setRunState(state, text){
		var $msg = $("#runStateMsg");
		$msg.removeClass("running success failed");
		if(state === "running"){
			$msg.addClass("running");
		}else if(state === "success"){
			$msg.addClass("success");
		}else if(state === "failed"){
			$msg.addClass("failed");
		}
		$msg.text(text);
	}

	function setSyncUiBusy(busy){
		isSyncRunning = busy === true;
		$("#syncStatusByDateBtn").prop("disabled", isSyncRunning);
		$("#syncDeleteByDateBtn").prop("disabled", isSyncRunning);
		$("#syncDateInput").prop("disabled", isSyncRunning);
	}

	var isRangeSyncRunning = false;

	function setRangeRunState(state, text){
		var $msg = $("#rangeRunStateMsg");
		$msg.removeClass("running success failed");
		if(state === "running"){
			$msg.addClass("running");
		}else if(state === "success"){
			$msg.addClass("success");
		}else if(state === "failed"){
			$msg.addClass("failed");
		}
		$msg.text(text);
	}

	function setRangeSyncUiBusy(busy){
		isRangeSyncRunning = busy === true;
		$("#rangeUpdateSyncBtn").prop("disabled", isRangeSyncRunning);
		$("#rangeDeleteSyncBtn").prop("disabled", isRangeSyncRunning);
		$("#rangeFromDateInput").prop("disabled", isRangeSyncRunning);
		$("#rangeToDateInput").prop("disabled", isRangeSyncRunning);
	}

	function buildStatusText(ext){
		return "Status direct send | date=" + (ext.syncDate || "")
			+ ", devices=" + (ext.devices || 0)
			+ ", onlineDevices=" + (ext.onlineDevices || 0)
			+ ", offlineDevices=" + (ext.offlineDevices || 0)
			+ ", users=" + (ext.users || 0)
			+ " (enable=" + (ext.enabledUsers || 0)
			+ ", disable=" + (ext.disabledUsers || 0) + ")"
			+ ", commandsSent=" + (ext.commandsSent || 0)
			+ " (enable=" + (ext.enableCommandsSent || 0)
			+ ", disable=" + (ext.disableCommandsSent || 0) + ")"
			+ ", plannedForOnlineDevices=" + (ext.commandsPlannedForOnlineDevices || 0)
			+ ", estimatedDispatchSeconds=" + (ext.estimatedDeviceDispatchSeconds || 0)
			+ ((ext.reason && ext.reason !== "null") ? ", reason=" + ext.reason : "");
	}

	function buildDeleteText(ext){
		return "Delete direct send | date=" + (ext.syncDate || "")
			+ ", devices=" + (ext.devices || 0)
			+ ", onlineDevices=" + (ext.onlineDevices || 0)
			+ ", offlineDevices=" + (ext.offlineDevices || 0)
			+ ", deletedUsers=" + (ext.deletedUsers || 0)
			+ ", commandsSent=" + (ext.commandsSent || 0)
			+ ", plannedForOnlineDevices=" + (ext.commandsPlannedForOnlineDevices || 0)
			+ ", estimatedDispatchSeconds=" + (ext.estimatedDeviceDispatchSeconds || 0)
			+ ((ext.reason && ext.reason !== "null") ? ", reason=" + ext.reason : "");
	}

	function buildRangeStatusText(ext){
		return "Status direct send | fromDate=" + (ext.fromDate || "")
			+ ", toDate=" + (ext.toDate || "")
			+ ", devices=" + (ext.devices || 0)
			+ ", onlineDevices=" + (ext.onlineDevices || 0)
			+ ", offlineDevices=" + (ext.offlineDevices || 0)
			+ ", users=" + (ext.users || 0)
			+ " (enable=" + (ext.enabledUsers || 0)
			+ ", disable=" + (ext.disabledUsers || 0) + ")"
			+ ", commandsSent=" + (ext.commandsSent || 0)
			+ " (enable=" + (ext.enableCommandsSent || 0)
			+ ", disable=" + (ext.disableCommandsSent || 0) + ")"
			+ ", batchSize=" + (ext.batchSize || 0)
			+ ", totalBatches=" + (ext.totalBatches || 0)
			+ ", plannedForOnlineDevices=" + (ext.commandsPlannedForOnlineDevices || 0)
			+ ", estimatedDispatchSeconds=" + (ext.estimatedDeviceDispatchSeconds || 0)
			+ ((ext.reason && ext.reason !== "null") ? ", reason=" + ext.reason : "");
	}

	function buildRangeDeleteText(ext){
		return "Delete direct send | fromDate=" + (ext.fromDate || "")
			+ ", toDate=" + (ext.toDate || "")
			+ ", devices=" + (ext.devices || 0)
			+ ", onlineDevices=" + (ext.onlineDevices || 0)
			+ ", offlineDevices=" + (ext.offlineDevices || 0)
			+ ", deletedUsers=" + (ext.deletedUsers || 0)
			+ ", commandsSent=" + (ext.commandsSent || 0)
			+ ", batchSize=" + (ext.batchSize || 0)
			+ ", totalBatches=" + (ext.totalBatches || 0)
			+ ", plannedForOnlineDevices=" + (ext.commandsPlannedForOnlineDevices || 0)
			+ ", estimatedDispatchSeconds=" + (ext.estimatedDeviceDispatchSeconds || 0)
			+ ((ext.reason && ext.reason !== "null") ? ", reason=" + ext.reason : "");
	}

	$(function(){
		$('#updateDataDatePicker').datetimepicker({
			format: 'yyyy-mm-dd',
			autoclose: true,
			minView: 2,
			language: 'en'
		});
		$('#rangeFromDatePicker').datetimepicker({
			format: 'yyyy-mm-dd',
			autoclose: true,
			minView: 2,
			language: 'en'
		});
		$('#rangeToDatePicker').datetimepicker({
			format: 'yyyy-mm-dd',
			autoclose: true,
			minView: 2,
			language: 'en'
		});
		$("#syncDateInput").val(formatDate(new Date()));
		$("#rangeFromDateInput").val(formatDate(new Date()));
		$("#rangeToDateInput").val(formatDate(new Date()));

		$("#syncStatusByDateBtn").click(function(){
			if(isSyncRunning){
				return;
			}
			var syncDate = getSelectedDate();
			if(syncDate === ""){
				setResult($("#syncStatusResult"), false, "Please select a date.");
				return;
			}
			setSyncUiBusy(true);
			setRunState("running", "Status sync is running for " + syncDate + ". Please wait...");
			setResult($("#syncStatusResult"), true, "Running direct status send for " + syncDate + " ...");
			$.ajax({
				url: "${APP_PATH}/syncUsersStatusByUpdDateAllDevices",
				type: "GET",
				cache: false,
				data: { syncDate: syncDate },
				success: function(result){
					var ext = (result && result.extend) ? result.extend : {};
					var text = buildStatusText(ext);
					var ok = result && result.code === 100;
					setResult($("#syncStatusResult"), ok, text + ((result && result.code !== 100 && ext.error) ? " | error=" + ext.error : ""));
					setRunState(ok ? "success" : "failed", ok ? ("Status sync SUCCESS for " + syncDate) : ("Status sync FAILED for " + syncDate));
				},
				error: function(){
					setResult($("#syncStatusResult"), false, "Direct status send failed for " + syncDate + ".");
					setRunState("failed", "Status sync FAILED for " + syncDate);
				},
				complete: function(){
					setSyncUiBusy(false);
				}
			});
		});

		$("#syncDeleteByDateBtn").click(function(){
			if(isSyncRunning){
				return;
			}
			var syncDate = getSelectedDate();
			if(syncDate === ""){
				setResult($("#syncDeleteResult"), false, "Please select a date.");
				return;
			}
			setSyncUiBusy(true);
			setRunState("running", "Delete sync is running for " + syncDate + ". Please wait...");
			setResult($("#syncDeleteResult"), true, "Running direct delete send for " + syncDate + " ...");
			$.ajax({
				url: "${APP_PATH}/syncUsersDeleteByDelDateAllDevices",
				type: "GET",
				cache: false,
				data: { syncDate: syncDate },
				success: function(result){
					var ext = (result && result.extend) ? result.extend : {};
					var text = buildDeleteText(ext);
					var ok = result && result.code === 100;
					setResult($("#syncDeleteResult"), ok, text + ((result && result.code !== 100 && ext.error) ? " | error=" + ext.error : ""));
					setRunState(ok ? "success" : "failed", ok ? ("Delete sync SUCCESS for " + syncDate) : ("Delete sync FAILED for " + syncDate));
				},
				error: function(){
					setResult($("#syncDeleteResult"), false, "Direct delete send failed for " + syncDate + ".");
					setRunState("failed", "Delete sync FAILED for " + syncDate);
				},
				complete: function(){
					setSyncUiBusy(false);
				}
			});
		});

		$("#rangeUpdateSyncBtn").click(function(){
			if(isRangeSyncRunning){
				return;
			}
			var fromDate = getRangeFromDate();
			var toDate = getRangeToDate();
			var validationError = validateRangeDates(fromDate, toDate);
			if(validationError !== ""){
				setResult($("#rangeSyncStatusResult"), false, validationError);
				return;
			}
			setRangeSyncUiBusy(true);
			setRangeRunState("running", "Update sync is running for " + fromDate + " to " + toDate + ". Please wait...");
			setResult($("#rangeSyncStatusResult"), true, "Running direct update sync for " + fromDate + " to " + toDate + " ...");
			$.ajax({
				url: "${APP_PATH}/syncUsersStatusByUpdDateRangeAllDevices",
				type: "GET",
				cache: false,
				data: { fromDate: fromDate, toDate: toDate },
				success: function(result){
					var ext = (result && result.extend) ? result.extend : {};
					var text = buildRangeStatusText(ext);
					var ok = result && result.code === 100;
					setResult($("#rangeSyncStatusResult"), ok, text + ((result && result.code !== 100 && ext.error) ? " | error=" + ext.error : ""));
					setRangeRunState(ok ? "success" : "failed", ok ? ("Update sync SUCCESS for " + fromDate + " to " + toDate) : ("Update sync FAILED for " + fromDate + " to " + toDate));
				},
				error: function(){
					setResult($("#rangeSyncStatusResult"), false, "Direct update sync failed for " + fromDate + " to " + toDate + ".");
					setRangeRunState("failed", "Update sync FAILED for " + fromDate + " to " + toDate);
				},
				complete: function(){
					setRangeSyncUiBusy(false);
				}
			});
		});

		$("#rangeDeleteSyncBtn").click(function(){
			if(isRangeSyncRunning){
				return;
			}
			var fromDate = getRangeFromDate();
			var toDate = getRangeToDate();
			var validationError = validateRangeDates(fromDate, toDate);
			if(validationError !== ""){
				setResult($("#rangeSyncDeleteResult"), false, validationError);
				return;
			}
			setRangeSyncUiBusy(true);
			setRangeRunState("running", "Delete sync is running for " + fromDate + " to " + toDate + ". Please wait...");
			setResult($("#rangeSyncDeleteResult"), true, "Running direct delete sync for " + fromDate + " to " + toDate + " ...");
			$.ajax({
				url: "${APP_PATH}/syncUsersDeleteByDelDateRangeAllDevices",
				type: "GET",
				cache: false,
				data: { fromDate: fromDate, toDate: toDate },
				success: function(result){
					var ext = (result && result.extend) ? result.extend : {};
					var text = buildRangeDeleteText(ext);
					var ok = result && result.code === 100;
					setResult($("#rangeSyncDeleteResult"), ok, text + ((result && result.code !== 100 && ext.error) ? " | error=" + ext.error : ""));
					setRangeRunState(ok ? "success" : "failed", ok ? ("Delete sync SUCCESS for " + fromDate + " to " + toDate) : ("Delete sync FAILED for " + fromDate + " to " + toDate));
				},
				error: function(){
					setResult($("#rangeSyncDeleteResult"), false, "Direct delete sync failed for " + fromDate + " to " + toDate + ".");
					setRangeRunState("failed", "Delete sync FAILED for " + fromDate + " to " + toDate);
				},
				complete: function(){
					setRangeSyncUiBusy(false);
				}
			});
		});
	});
</script>
</body>
</html>
