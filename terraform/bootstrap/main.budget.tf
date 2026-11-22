# The backstop for a surprise bill. There is no credit here, unlike Azure's
# $150: everything is billed. Expected spend is under a dollar a month.
#
# Emails the billing account's administrators (the default recipients) at
# half the budget, at the budget, and when the month is forecast to reach it.
# A budget alerts; it never stops anything.
resource "google_billing_budget" "monthly" {
  provider = google.platform

  billing_account = var.billing_account
  display_name    = "jay-withers monthly"

  amount {
    specified_amount {
      # No currency_code: the billing account's own currency, whatever it is.
      units = tostring(var.budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }

  threshold_rules {
    threshold_percent = 1.0
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  depends_on = [google_project_service.this]
}
