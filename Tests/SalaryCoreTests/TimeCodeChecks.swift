import Foundation
import SalaryCore

func checkTimeCode() {
    precondition(TimeCode.format(0) == "00:00")
    precondition(TimeCode.format(9 * 60 + 5) == "09:05")
    precondition(TimeCode.format(18 * 60) == "18:00")
    precondition(TimeCode.format(-10) == "00:00")
    precondition(TimeCode.format(24 * 60) == "23:59")

    precondition(TimeCode.parse("9") == 9 * 60)
    precondition(TimeCode.parse("09") == 9 * 60)
    precondition(TimeCode.parse("930") == 9 * 60 + 30)
    precondition(TimeCode.parse("0930") == 9 * 60 + 30)
    precondition(TimeCode.parse("9:30") == 9 * 60 + 30)
    precondition(TimeCode.parse("1:2") == 62)
    precondition(TimeCode.parse("18:") == 18 * 60)
    precondition(TimeCode.parse("0:05") == 5)
    precondition(TimeCode.parse("23:59") == 23 * 60 + 59)
    precondition(TimeCode.parse("24:00") == nil)
    precondition(TimeCode.parse("12:60") == nil)
    precondition(TimeCode.parse("") == nil)
    precondition(TimeCode.parse("abc") == nil)
    precondition(TimeCode.parse("12345") == nil)

    precondition(TimeCode.sanitize("1800") == "1800")
    precondition(TimeCode.sanitize("1a:2:3") == "1:23")
    precondition(TimeCode.sanitize("12345") == "1234")
    precondition(TimeCode.sanitize(":30") == "30")
    precondition(TimeCode.sanitize("  ") == "")
}
