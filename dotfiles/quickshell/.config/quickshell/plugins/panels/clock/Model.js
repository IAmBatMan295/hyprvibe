var MS_PER_DAY = 86400000

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

if (typeof module !== "undefined") {
  module.exports = {
    isoWeek: isoWeek,
    isoWeekLiteral: isoWeekLiteral
  }
}
