function formatToCronSchedule(value) {
  if (value === void 0) {
    return "*";
  } else if (typeof value === "number") {
    return value.toString();
  } else {
    const { exact } = value;
    if (exact === void 0) {
      const { start, end, every } = value;
      if (start !== void 0 && end !== void 0 && every !== void 0) {
        return `${start}-${end}/${every}`;
      } else if (start !== void 0 && end !== void 0) {
        return `${start}-${end}`;
      } else if (start !== void 0 && every !== void 0) {
        return `${start}/${every}`;
      } else if (start !== void 0) {
        return `${start}/1`;
      } else if (end === void 0 && every !== void 0) {
        return `*/${every}`;
      } else {
        throw new TypeError("Invalid cron schedule");
      }
    } else {
      if (typeof exact === "number") {
        return exact.toString();
      } else {
        return exact.join(",");
      }
    }
  }
}
function parseScheduleToString(schedule) {
  if (typeof schedule === "string") {
    return schedule;
  } else {
    const { minute, hour, dayOfMonth, month, dayOfWeek } = schedule;
    return `${formatToCronSchedule(minute)} ${formatToCronSchedule(hour)} ${formatToCronSchedule(
      dayOfMonth
    )} ${formatToCronSchedule(month)} ${formatToCronSchedule(dayOfWeek)}`;
  }
}

export { parseScheduleToString };
//# sourceMappingURL=deno-cron-format.js.map
