// Allow the Elisity master account to manage this account.
resource "aws_iam_role" "mgmt-master" {
  count = local.manage_customer_role ? 1 : 0
  name = "${local.customer_subdomain}OrganizationAccountAccess"

  assume_role_policy = data.aws_iam_policy_document.mgmt-master-assume_role[0].json
}

resource "aws_iam_policy" "mgmt-master" {
  count = local.manage_customer_role ? 1 : 0
  name = "${local.customer_subdomain}OrganizationAccountAccessRole"
  policy = data.aws_iam_policy_document.mgmt-master[0].json
}

resource "aws_iam_role_policy_attachment" "mgmt-master" {
  count = local.manage_customer_role ? 1 : 0
  role = aws_iam_role.mgmt-master[0].name
  policy_arn = aws_iam_policy.mgmt-master[0].arn
}

// FIXME:  Get a list of required APIs from Elisity, and make this least-priviledge.
data "aws_iam_policy_document" "mgmt-master" {
  count = local.manage_customer_role ? 1 : 0

  statement {
    sid = "AdminAccess"
    effect = "Allow"
    actions = [ "*" ]
    resources = [ "*" ]
  }
}

// FIXME:  Don't let the whole account assume it, lock this down to a role.
data "aws_iam_policy_document" "mgmt-master-assume_role" {
  count = local.manage_customer_role ? 1 : 0

  statement {
    sid     = "AssumeRoleByElisityMaster"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [ "arn:aws:iam::${local.master_account_id}:root" ]
    }

    condition {
      test = "StringEquals"
      values = [ local.customer_role_external_id ]
      variable = "sts:ExternalId"
    }
  }
}
