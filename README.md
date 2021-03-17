# aws: AWS command line

When AWS was new (mid 2000s), Amazon didn't have a decent command line tool, so I wrote AWS. It was exceeding popular and was ranked by Amazon as the #1 community-contributed software for all of AWS.

(For a long time, aws had 14 5-star reviews. Eventually, somebody gave aws a 4-star review, saying, "I save 5 stars for software that is so good, it doesn't exist yet."
At that point, Amazon's ranking system dropped the rating below anothyer project that had a total of one 5-star review.
I suggested to Amazon that it didn't seem fair, and they reworked their ranking system, so that aws was again #1. It stayed there for the first few years of AWS.)

Amazon has added lots of tools, and aws was maintained by me alone. It still works, and I use it, but I no longer spend much time supporting it.

"aws" is a command line program that accesses Amazon Web Services: EC2, S3, SQS, SDB, ELB, IAM, EBN, RDS

To run "aws", all you need is a single file!

1. download https://raw.github.com/timkay/aws/master/aws
2. make it executable
3. create ~/.awssecret or set EC2_ACCESS_KEY and EC2_SECRET_KEY

and you are done.

For more documentation, see http://timkay.com/aws/ and also the GitHub Wiki.
