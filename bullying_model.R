# Bullying risk among U.S. children: NSCH 2017
# Outcome: was the child bullied, picked on, or excluded (any vs. none)
# Data: 2017 National Survey of Children's Health, topical file (U.S. Census Bureau)
#   https://www2.census.gov/programs-surveys/nsch/datasets/2017/nsch_2017_topical_Stata.zip
#   Unzip into data/ before running.

library(haven)
library(dplyr)
library(car)
library(survey)

df <- read_dta("data/nsch_2017e_topical.dta") %>% zap_labels()

# The bullying question is asked for children aged 6 to 17:
# "This child is bullied, picked on, or excluded by other children"
# 1 = Definitely true, 2 = Somewhat true, 3 = Not true
yes_no <- function(x) case_when(x == 1 ~ 1, x == 2 ~ 0, TRUE ~ NA_real_)

model_df <- df %>%
  filter(sc_age_years >= 6, sc_age_years <= 17) %>%
  transmute(
    bullied    = case_when(bullied %in% c(1, 2) ~ 1, bullied == 3 ~ 0, TRUE ~ NA_real_),
    age        = sc_age_years,
    female     = case_when(sc_sex == 2 ~ 1, sc_sex == 1 ~ 0),
    race       = factor(sc_race_r, levels = c(1, 2, 3, 4, 5, 7),
                        labels = c("White", "Black", "American Indian/Alaska Native", "Asian",
                                   "Native Hawaiian/Pacific Islander", "Two or more races")),
    adhd       = yes_no(k2q31a),
    depression = yes_no(k2q32a),
    pain       = yes_no(physicalpain),
    parent_edu = factor(higrade, levels = 1:3,
                        labels = c("Less than high school", "High school", "More than high school")),
    fwc, fipsst, stratum, hhid
  ) %>%
  filter(complete.cases(.))

cat("Children aged 6 to 17 with complete data:", nrow(model_df), "\n")
cat("Share ever bullied (unweighted):", round(mean(model_df$bullied) * 100, 1), "%\n")

# Multicollinearity check
print(vif(lm(bullied ~ age + female + race + adhd + depression + pain + parent_edu, data = model_df)))

# 1) Logistic regression
fit <- glm(bullied ~ age + female + race + adhd + depression + pain + parent_edu,
           data = model_df, family = binomial)
summary(fit)

or_table <- function(m) {
  ci <- suppressMessages(confint.default(m))
  round(cbind(OR = exp(coef(m)), lower = exp(ci[, 1]), upper = exp(ci[, 2]),
              p = summary(m)$coefficients[, 4]), 3)
}
print(or_table(fit))

# 2) Survey-weighted logistic regression (national estimates)
design <- svydesign(ids = ~hhid, strata = ~interaction(fipsst, stratum),
                    weights = ~fwc, data = model_df, nest = TRUE)
cat("Weighted share ever bullied:", round(coef(svymean(~bullied, design)) * 100, 1), "%\n")
fit_w <- svyglm(bullied ~ age + female + race + adhd + depression + pain + parent_edu,
                design = design, family = quasibinomial())
print(or_table(fit_w))

# Model fit
null <- glm(bullied ~ 1, data = model_df, family = binomial)
cat("McFadden pseudo R2:", round(1 - logLik(fit) / logLik(null), 3), "\n")
cat("AUC:", round(pROC_auc <- {
  p <- fitted(fit); y <- model_df$bullied
  r <- rank(p); (sum(r[y == 1]) - sum(y == 1) * (sum(y == 1) + 1) / 2) / (sum(y == 1) * sum(y == 0))
}, 3), "\n")

# Save odds ratios and a forest plot
dir.create("results", showWarnings = FALSE)
w <- or_table(fit_w)[-1, ]
rownames(w) <- sub("^race", "Race: ", sub("^parent_edu", "Parent education: ", rownames(w)))
rownames(w) <- c(age = "Age (per year)", female = "Female", adhd = "ADHD", depression = "Depression",
                 pain = "Chronic physical pain")[rownames(w)] %>% coalesce(rownames(w))
write.csv(w, "results/odds_ratios_weighted.csv")
png("results/odds_ratios.png", width = 1600, height = 1000, res = 200)
par(mar = c(4, 17, 2, 1))
ord <- order(w[, "OR"])
plot(w[ord, "OR"], seq_along(ord), log = "x", pch = 19, xlim = range(w[, c("lower", "upper")]),
     yaxt = "n", ylab = "", xlab = "Odds ratio of being bullied (log scale, 95% CI)",
     main = "What predicts being bullied? (NSCH 2017, ages 6 to 17)")
segments(w[ord, "lower"], seq_along(ord), w[ord, "upper"], seq_along(ord))
axis(2, at = seq_along(ord), labels = rownames(w)[ord], las = 1, cex.axis = 0.8)
abline(v = 1, lty = 2, col = "grey40")
dev.off()
